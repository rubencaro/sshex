require SSHEx.Helpers, as: H

defmodule SSHEx do

  @moduledoc """
    Module to deal with SSH connections. It uses low level erlang
    [ssh library](http://www.erlang.org/doc/man/ssh.html).

    :ssh.start # just in case
    {:ok, conn} = :ssh.connect('123.123.123.123',22,[ {:user,'myuser'},{:silently_accept_hosts, true} ], 5000)
  """

  @doc """
    Gets an open SSH connection reference (as returned by `:ssh.connect/4`),
    and a command to execute.

    Optionally it gets a `channel_timeout` for the underlying SSH channel opening,
    and an `exec_timeout` for the execution itself. Both default to 5000ms.

    Any failure related with the SSH connection itself is raised without mercy.

    Returns `{:ok,data,status}` on success. Otherwise `{:error, details}`.

    If `:separate_streams` is `true` then the response on success looks like `{:ok,stdout,stderr,status}`.

    Ex:

    ```
    {:ok, _, 0} = SSHEx.run conn, 'rm -fr /something/to/delete'
    {:ok, res, 0} = SSHEx.run conn, 'ls /some/path'
    {:ok, stdout, stderr, 2} = SSHEx.run conn, 'ls /nonexisting/path', separate_streams: true
    ```
  """
  def run(conn, cmd, opts \\ []) do
    opts = opts |> H.defaults(connection_module: :ssh_connection,
                              channel_timeout: 5000,
                              exec_timeout: 5000)
    conn
    |> open_channel_and_exec(cmd, opts)
    |> get_response(opts[:exec_timeout], "", "", nil, false, opts)
  end

  @doc """
    Convenience function to run `run/3` and get output string straight from it,
    like `:os.cmd/1`.

    See `run/3` for options.

    Returns `response` only if `run/3` return value matches `{:ok, response, _}`,
    or returns `{stdout, stderr}` if `run/3` returns `{:ok, stdout, stderr, _}`.
    Raises any `{:error, details}` returned by `run/3`. Note return status from
    `cmd` is ignored.

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

    Optionally it gets a timeout for the underlying SSH channel opening,
    and for the execution itself.

    Supported options are:

    * `:channel_timeout`
    * `:exec_timeout`
    * `:connection_module`

    Any failure related with the SSH connection itself is raised without mercy (by now).

    Returns a `Stream` that you can use to lazily retrieve each line of output
    for the given command.

    Each iteration of the stream will read from the underlying connection and
    return one of these:

    * `{:stdout,row}`
    * `{:stderr,row}`
    * `{:status,status}`

    Keep in mind that rows may not be received in order.

    Ex:
    ```
      {:ok, conn} = :ssh.connect('123.123.123.123', 22,
                    [ {:user,'myuser'}, {:silently_accept_hosts, true} ], 5000)

      str = SSHEx.stream conn, 'somecommand'

      Stream.each(str, fn(x)->
        case x do
          {:stdout,row}    -> process_output(row)
          {:stderr,row}    -> process_error(row)
          {:status,status} -> process_exit_status(status)
        end
      end)
    ```
  """
  def stream(conn, cmd, opts \\ []) do
    opts = opts |> H.defaults(connection_module: :ssh_connection,
                              channel_timeout: 5000,
                              exec_timeout: 5000)

    start_fun = fn-> open_channel_and_exec(conn,cmd,opts) end

    next_fun = fn(channel)->
      if channel == :halt_next do # halt if asked
        {:halt, 'Halt requested on previous iteration'}
      else
        res = receive_and_parse_response(channel, opts[:exec_timeout])
        case res do
          {:loop, {_, _, "", "", nil, false}} -> {[], channel}
          {:loop, {_, _,  x, "", nil, false}} -> {[ {:stdout,x} ], channel}
          {:loop, {_, _, "",  x, nil, false}} -> {[ {:stderr,x} ], channel}
          {:loop, {_, _, "", "",   x, false}} -> {[ {:status,x} ], channel}
          {:loop, {_, _, "", "", nil, true }} -> {:halt, channel}
          # TODO: wait until 2.0 to really handle errors
          # {:error, reason} = x -> {[x], :halt_next} # emit error, then halt
          any -> raise inspect(any)
        end
      end
    end

    after_fun = fn(_)-> end

    Stream.resource start_fun, next_fun, after_fun
  end

  # Try to get the channel, and then execute the given command.
  # Just a DRY to call internal `open_channel/3` and `exec/5`.
  # Raise if anything fails.
  #
  defp open_channel_and_exec(conn, cmd, opts) do
    conn
    |> open_channel(opts[:channel_timeout], opts[:connection_module])
    |> exec(conn, cmd, opts[:exec_timeout], opts[:connection_module])
  end

  # Try to get the channel, raise if it's not working
  #
  defp open_channel(conn, channel_timeout, connection_module) do
    res = connection_module.session_channel(conn, channel_timeout)
    case res do
      { :ok, channel } -> channel
      any -> raise inspect(any)
    end
  end

  # Execute the given command, raise if it fails
  #
  defp exec(channel, conn, cmd, exec_timeout, connection_module) do
    res = connection_module.exec(conn, channel, cmd, exec_timeout)
    case res do
      :failure -> raise "Could not exec '#{cmd}'!"
      :success -> channel
      any -> raise inspect(any)
    end
  end

  # Loop until all data is received. Return read data and the exit_status.
  #
  defp get_response(channel, timeout, stdout, stderr, status, closed, opts) do

    # if we got status and closed, then we are done
    parsed = case {status, closed} do
      {st, true} when not is_nil(st) -> format_response({:ok, stdout, stderr, status}, opts)
      _ -> receive_and_parse_response(channel, timeout, stdout, stderr, status, closed)
    end

    # tail recursion
    case parsed do
      {:loop, {ch, tout, out, err, st, cl}} -> # loop again, still things missing
        get_response(ch, tout, out, err, st, cl, opts)
      x -> x
    end
  end

  # Parse ugly response
  #
  defp receive_and_parse_response(chn, tout, stdout \\ "", stderr \\ "", status \\ nil, closed \\ false) do
    response = receive do
      {:ssh_cm, _, res} -> res
    after
      tout -> { :error, :taimaut }
    end

    case response do
      {:data, ^chn, 1, new_data} ->       {:loop, {chn, tout, stdout, stderr <> new_data, status, closed}}
      {:data, ^chn, 0, new_data} ->       {:loop, {chn, tout, stdout <> new_data, stderr, status, closed}}
      {:eof, ^chn} ->                     {:loop, {chn, tout, stdout, stderr, status, closed}}
      {:exit_signal, ^chn, _, _} ->       {:loop, {chn, tout, stdout, stderr, status, closed}}
      {:exit_status, ^chn, new_status} -> {:loop, {chn, tout, stdout, stderr, new_status, closed}}
      {:closed, ^chn} ->                  {:loop, {chn, tout, stdout, stderr, status, true}}
      any -> raise inspect(any)
    end
  end

  # Format response for given raw response and given options
  #
  defp format_response(raw, opts) do
    case opts[:separate_streams] do
      true -> raw
      _ -> {:ok, stdout, stderr, status} = raw
           {:ok, stdout <> stderr, status}
    end
  end

end
