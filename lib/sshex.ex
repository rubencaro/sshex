require SSHEx.Helpers, as: H

defmodule SSHEx do
  @moduledoc """
    Module to deal with SSH connections. It uses low level erlang
    [ssh library](http://www.erlang.org/doc/man/ssh.html).

    :ssh.start # just in case
    {:ok, conn} = SSHEx.connect ip: '123.123.123.123', user: 'myuser'
  """

  @doc """
    Establish a connection with given options. Uses `:ssh.connect/4` for that.

    Recognised options are `ip` (mandatory), `port` and `negotiation_timeout`.
    Any other option is passed to `:ssh.connect/4` as is
    (so be careful if you use binaries and `:ssh` expects char lists...).
    See [its reference](http://erlang.org/doc/man/ssh.html#connect-4) for available options.

    Default values exist for some options, which are:
    * `port`: 22
    * `negotiation_timeout`: 5000
    * `silently_accept_hosts`: `true`

    Returns `{:ok, connection}`, or `{:error, reason}`.
  """
  def connect(opts) do
    opts =
      opts
      |> H.convert_values()
      |> H.defaults(
        port: 22,
        negotiation_timeout: 5000,
        silently_accept_hosts: true,
        ssh_module: :ssh
      )

    own_keys = [:ip, :port, :negotiation_timeout, :ssh_module]

    ssh_opts = opts |> Enum.filter(fn {k, _} -> k not in own_keys end)

    opts[:ssh_module].connect(opts[:ip], opts[:port], ssh_opts, opts[:negotiation_timeout])
  end

  @doc """
    Gets an open SSH connection reference (as returned by `:ssh.connect/4`),
    and a command to execute.

    Optionally it gets a `channel_timeout` for the underlying SSH channel opening,
    and an `exec_timeout` for the execution itself. Both default to 5000ms.

    Returns `{:ok,data,status}` on success. Otherwise `{:error, details}`.

    If `:separate_streams` is `true` then the response on success looks like `{:ok,stdout,stderr,status}`.

    Ex:

    ```
    {:ok, _, 0} = SSHEx.run conn, 'rm -fr /something/to/delete'
    {:ok, res, 0} = SSHEx.run conn, 'ls /some/path'
    {:error, reason} = SSHEx.run failing_conn, 'ls /some/path'
    {:ok, stdout, stderr, 2} = SSHEx.run conn, 'ls /nonexisting/path', separate_streams: true
    ```
  """
  def run(conn, cmd, opts \\ []) do
    opts =
      opts
      |> H.convert_values()
      |> H.defaults(
        connection_module: :ssh_connection,
        channel_timeout: 5000,
        exec_timeout: 5000
      )

    cmd = H.convert_value(cmd)

    case open_channel_and_exec(conn, cmd, opts) do
      {:error, r} -> {:error, r}
      chn -> get_response(conn, chn, opts[:exec_timeout], "", "", nil, false, opts)
    end
  end

  @doc """
    Convenience function to run `run/3` and get output string straight from it,
    like `:os.cmd/1`.

    See `run/3` for options.

    Returns `response` only if `run/3` return value matches `{:ok, response, _}`,
    or returns `{stdout, stderr}` if `run/3` returns `{:ok, stdout, stderr, _}`.
    Raises any `{:error, details}` returned by `run/3`. Note return status from
    `cmd` is also ignored.

    Ex:

    ```
        SSHEx.cmd! conn, 'mkdir -p /path/to/newdir'
        res = SSHEx.cmd! conn, 'ls /some/path'
    ```
  """
  def cmd!(conn, cmd, opts \\ []) do
    case run(conn, cmd, opts) do
      {:ok, response, _} -> response
      {:ok, stdout, stderr, _} -> {stdout, stderr}
      any -> raise inspect(any)
    end
  end

  @doc """
    Gets an open SSH connection reference (as returned by `:ssh.connect/4`),
    and a command to execute.

    See `run/3` for options.

    Returns a `Stream` that you can use to lazily retrieve each line of output
    for the given command.

    Each iteration of the stream will read from the underlying connection and
    return one of these:

    * `{:stdout,row}`
    * `{:stderr,row}`
    * `{:status,status}`
    * `{:error,reason}`

    Keep in mind that rows may not be received in order.

    Ex:
    ```
      {:ok, conn} = :ssh.connect('123.123.123.123', 22,
                    [ {:user,'myuser'}, {:silently_accept_hosts, true} ], 5000)

      str = SSHEx.stream conn, 'somecommand'

      Stream.each(str, fn(x)->
        case x do
          {:stdout,row}    -> process_stdout(row)
          {:stderr,row}    -> process_stderr(row)
          {:status,status} -> process_exit_status(status)
          {:error,reason}  -> process_error(row)
        end
      end)
    ```
  """
  def stream(conn, cmd, opts \\ []) do
    opts =
      opts
      |> H.convert_values()
      |> H.defaults(
        connection_module: :ssh_connection,
        channel_timeout: 5000,
        exec_timeout: 5000
      )

    cmd = H.convert_value(cmd)
    start_fun = fn -> open_channel_and_exec(conn, cmd, opts) end

    next_fun = fn input ->
      case input do
        :halt_next -> {:halt, ~c"Halt requested on previous iteration"}
        # emit error, then halt
        {:error, _} = x -> {[x], :halt_next}
        chn -> do_stream_next(conn, chn, opts)
      end
    end

    after_fun = fn channel ->
      :ok = opts[:connection_module].close(conn, channel)
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  # Actual mapping of `:ssh` responses into streamable chunks
  #
  defp do_stream_next(conn, channel, opts) do
    case receive_and_parse_response(conn, channel, opts[:connection_module], opts[:exec_timeout]) do
      {:loop, {_, _, "", "", nil, false}} -> {[], channel}
      {:loop, {_, _, x, "", nil, false}} -> {[{:stdout, x}], channel}
      {:loop, {_, _, "", x, nil, false}} -> {[{:stderr, x}], channel}
      {:loop, {_, _, "", "", x, false}} -> {[{:status, x}], channel}
      {:loop, {_, _, "", "", nil, true}} -> {:halt, channel}
      # emit error, then halt
      {:error, _} = x -> {[x], :halt_next}
    end
  end

  # Try to get the channel, and then execute the given command.
  # Just a DRY to call internal `open_channel/3` and `exec/5`.
  #
  defp open_channel_and_exec(conn, cmd, opts) do
    case open_channel(conn, opts[:channel_timeout], opts[:connection_module]) do
      {:error, r} -> {:error, r}
      {:ok, chn} -> exec(chn, conn, cmd, opts[:exec_timeout], opts[:connection_module])
    end
  end

  # Try to get the channel
  #
  defp open_channel(conn, channel_timeout, connection_module) do
    connection_module.session_channel(conn, channel_timeout)
  end

  # Execute the given command. Map every error to `{:error,reason}`.
  #
  defp exec(channel, conn, cmd, exec_timeout, connection_module) do
    case connection_module.exec(conn, channel, cmd, exec_timeout) do
      :success -> channel
      :failure -> {:error, "Could not exec '#{cmd}'!"}
      # {:error, reason}
      any -> any
    end
  end

  # Loop until all data is received. Return read data and the exit_status.
  #
  defp get_response(conn, channel, timeout, stdout, stderr, status, closed, opts) do
    # if we got status and closed, then we are done
    parsed =
      case {status, closed} do
        {st, true} when not is_nil(st) ->
          format_response({:ok, stdout, stderr, status}, opts)

        _ ->
          receive_and_parse_response(
            conn,
            channel,
            opts[:connection_module],
            timeout,
            stdout,
            stderr,
            status,
            closed
          )
      end

    # tail recursion
    case parsed do
      # loop again, still things missing
      {:loop, {ch, tout, out, err, st, cl}} ->
        get_response(conn, ch, tout, out, err, st, cl, opts)

      x ->
        x
    end
  end

  # Parse ugly response
  #
  defp receive_and_parse_response(
         conn,
         chn,
         connection_module,
         tout,
         stdout \\ "",
         stderr \\ "",
         status \\ nil,
         closed \\ false
       ) do
    response =
      receive do
        {:ssh_cm, ^conn, res} -> res
      after
        tout -> {:error, "Timeout. Did not receive data for #{tout}ms."}
      end

    # call adjust_window to allow more data income, but only when needed
    case response do
      {:data, ^chn, _, new_data} ->
        connection_module.adjust_window(conn, chn, byte_size(new_data))

      _ ->
        :ok
    end

    case response do
      {:data, ^chn, 1, new_data} ->
        {:loop, {chn, tout, stdout, stderr <> new_data, status, closed}}

      {:data, ^chn, 0, new_data} ->
        {:loop, {chn, tout, stdout <> new_data, stderr, status, closed}}

      {:eof, ^chn} ->
        {:loop, {chn, tout, stdout, stderr, status, closed}}

      {:exit_signal, ^chn, _, _} ->
        {:loop, {chn, tout, stdout, stderr, status, closed}}

      {:exit_signal, ^chn, _, _, _} ->
        {:loop, {chn, tout, stdout, stderr, status, closed}}

      {:exit_status, ^chn, new_status} ->
        {:loop, {chn, tout, stdout, stderr, new_status, closed}}

      {:closed, ^chn} ->
        {:loop, {chn, tout, stdout, stderr, status, true}}

      # {:error, reason}
      any ->
        any
    end
  end

  # Format response for given raw response and given options
  #
  defp format_response(raw, opts) do
    case opts[:separate_streams] do
      true ->
        raw

      _ ->
        {:ok, stdout, stderr, status} = raw
        {:ok, stdout <> stderr, status}
    end
  end
end
