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
  """
  def run(conn, cmd, channel_timeout \\ 5000, exec_timeout \\ 5000) do
    conn
    |> open_channel(channel_timeout)
    |> exec(conn, cmd, exec_timeout)
    |> get_response(exec_timeout)
  end

  @doc """
    Convenience function to run `run/4` and get output string straight from it,
    like `:os.cmd/1`.

    Returns `response` only if `run/4` return value matches `{:ok, response, _}`.
    Raises any `{:error, details}` returned by `run/4`. Note return status from
    `cmd` is ignored.
  """
  def cmd!(conn, cmd, channel_timeout \\ 5000, exec_timeout \\ 5000) do
    case run(conn, cmd, channel_timeout, exec_timeout) do
      {:ok, response, _} -> response
      any -> raise inspect(any)
    end
  end

  # Try to get the channel, raise if it's not working
  #
  defp open_channel(conn, channel_timeout) do
    res = :ssh_connection.session_channel(conn, channel_timeout)
    case res do
      { :error, reason } -> raise reason
      { :ok, channel } -> channel
    end
  end

  # Execute the given command, raise if it fails
  #
  defp exec(channel, conn, cmd, exec_timeout) do
    res = :ssh_connection.exec(conn, channel, cmd, exec_timeout)
    case res do
      :failure -> raise "Could not exec #{cmd}!"
      :success -> channel
    end
  end

  # Loop until all data is received. Return read data and the exit_status.
  #
  defp get_response(channel, timeout, data \\ "", status \\ nil, closed \\ false) do

    # if we got status and closed, then we are done
    parsed = case {status, closed} do
      {st, true} when not is_nil(st) -> {:ok, data, status}
      _ -> receive_and_parse_response(channel, timeout, data, status, closed)
    end

    # tail recursion
    case parsed do
      {:loop, {channel, timeout, data, status, closed}} -> # loop again, still things missing
        get_response(channel, timeout, data, status, closed)
      x -> x
    end
  end

  # Parse ugly response
  #
  defp receive_and_parse_response(chn, tout, data, status, closed) do
    response = receive do
      {:ssh_cm, _, res} -> res
    after
      tout -> { :error, :taimaut }
    end

    case response do
      {:data, ^chn, _, new_data} ->       {:loop, {chn, tout, data <> new_data, status, closed}}
      {:eof, ^chn} ->                     {:loop, {chn, tout, data, status, closed}}
      {:exit_signal, ^chn, _, _} ->       {:loop, {chn, tout, data, status, closed}}
      {:exit_status, ^chn, new_status} -> {:loop, {chn, tout, data, new_status, closed}}
      {:closed, ^chn} ->                  {:loop, {chn, tout, data, status, true}}
      x -> x
    end
  end

end
