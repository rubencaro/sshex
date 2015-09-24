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

    Optionally it gets a timeout for the underlying SSH channel opening,
    and for the execution itself.

    Any failure related with the SSH connection itself is raised without mercy.

    Returns `{:ok,data,status}` on success. Otherwise `{:error, details}`.

    If `:separate_streams` is `true` then the response on success looks like `{:ok,stdout,stderr,status}`.

    TODO: For 2.0 release, join every optional argument into one big opts list
  """
  def run(conn, cmd, channel_timeout \\ 5000, exec_timeout \\ 5000, opts \\ []) do
    conn
    |> open_channel(channel_timeout)
    |> exec(conn, cmd, exec_timeout)
    |> get_response(exec_timeout, "", "", nil, false, opts)
  end

  @doc """
    Convenience function to run `run/5` and get output string straight from it,
    like `:os.cmd/1`.

    Returns `response` only if `run/5` return value matches `{:ok, response, _}`,
    or returns `{stdout, stderr}` if `run/5` returns `{:ok, stdout, stderr, _}`.
    Raises any `{:error, details}` returned by `run/5`. Note return status from
    `cmd` is ignored.

    TODO: For 2.0 release, join every optional argument into one big opts list
  """
  def cmd!(conn, cmd, channel_timeout \\ 5000, exec_timeout \\ 5000, opts \\ []) do
    case run(conn, cmd, channel_timeout, exec_timeout, opts) do
      {:ok, response, _} -> response
      {:ok, stdout, stderr, _} -> {stdout, stderr}
      any -> raise inspect(any)
    end
  end

  # Try to get the channel, raise if it's not working
  #
  defp open_channel(conn, channel_timeout) do
    res = :ssh_connection.session_channel(conn, channel_timeout)
    case res do
      { :ok, channel } -> channel
      any -> raise inspect(any)
    end
  end

  # Execute the given command, raise if it fails
  #
  defp exec(channel, conn, cmd, exec_timeout) do
    res = :ssh_connection.exec(conn, channel, cmd, exec_timeout)
    case res do
      :failure -> raise "Could not exec '#{cmd}'!"
      :success -> channel
      any -> raise inspect(any)
    end
  end

  # Loop until all data is received. Return read data and the exit_status.
  #
  #  TODO: For 2.0 release, join every optional argument into one big opts list
  #
  defp get_response(channel, timeout, stdout, stderr, status, closed, opts) do

    # if we got status and closed, then we are done
    parsed = case {status, closed} do
      {st, true} when not is_nil(st) -> format_response({:ok, stdout, stderr, status}, opts)
      _ -> receive_and_parse_response(channel, timeout, stdout, stderr, status, closed)
    end

    # tail recursion
    case parsed do
      {:loop, {channel, timeout, stdout, stderr, status, closed}} -> # loop again, still things missing
        get_response(channel, timeout, stdout, stderr, status, closed, opts)
      x -> x
    end
  end

  # Parse ugly response
  defp receive_and_parse_response(chn, tout, stdout, stderr, status, closed) do
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
  defp format_response(raw, opts) do
    case opts[:separate_streams] do
      true -> raw
      _ -> {:ok, stdout, stderr, status} = raw
           {:ok, stdout <> stderr, status}
    end
  end

end
