defmodule SSHExTest do
  use ExUnit.Case

  test "connect" do
    opts = [ip: ~c"123.123.123.123", user: ~c"myuser", ssh_module: AllOKMock]

    assert SSHEx.connect(opts) == {:ok, :mocked}
  end

  test "Plain `cmd!`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    # any would do
    status = 123
    send_regular_sequence(mocked_data, status)

    # actually test it
    assert SSHEx.cmd!(:mocked, ~c"somecommand", connection_module: AllOKMock) == mocked_data
  end

  test "String `cmd!`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    # any would do
    status = 123
    send_regular_sequence(mocked_data, status)

    # actually test it
    assert SSHEx.cmd!(:mocked, "somecommand", connection_module: AllOKMock) == mocked_data
  end

  test "Plain `run`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    # any would do
    status = 123
    send_regular_sequence(mocked_data, status)

    assert SSHEx.run(:mocked, ~c"somecommand", connection_module: AllOKMock) ==
             {:ok, mocked_data, status}
  end

  test "String `run`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    # any would do
    status = 123
    send_regular_sequence(mocked_data, status)

    assert SSHEx.run(:mocked, "somecommand", connection_module: AllOKMock) ==
             {:ok, mocked_data, status}
  end

  test "Stream long response" do
    lines = ["some", "long", "output", "sequence"]
    send_long_sequence(lines)

    response =
      Enum.map(lines, &{:stdout, &1}) ++
        [
          {:stderr, "mockederror"},
          {:status, 0}
        ]

    str = SSHEx.stream(:mocked, ~c"somecommand", connection_module: AllOKMock)
    assert Enum.to_list(str) == response
  end

  test "Separate streams" do
    # send mocked response sequence to the mailbox
    mocked_stdout = "output"
    mocked_stderr = "something failed"
    send_separated_sequence(mocked_stdout, mocked_stderr)

    # actually test it
    res =
      SSHEx.run(:mocked, ~c"failingcommand", connection_module: AllOKMock, separate_streams: true)

    assert res == {:ok, mocked_stdout, mocked_stderr, 2}
  end

  test "`:ssh` error message when `run`" do
    send(self(), {:ssh_cm, :mocked, {:error, :reason}})
    assert SSHEx.run(:mocked, ~c"somecommand", connection_module: AllOKMock) == {:error, :reason}
  end

  test "`:ssh` error message when `cmd!`" do
    send(self(), {:ssh_cm, :mocked, {:error, :reason}})

    assert_raise RuntimeError, "{:error, :reason}", fn ->
      SSHEx.cmd!(:mocked, ~c"somecommand", connection_module: AllOKMock)
    end
  end

  test "`:ssh` error message while `stream`" do
    lines = ["some", "long", "output", "sequence"]
    send_long_sequence(lines, error: true)
    response = Enum.map(lines, &{:stdout, &1}) ++ [{:error, :reason}]

    str = SSHEx.stream(:mocked, ~c"somecommand", connection_module: AllOKMock)
    assert Enum.to_list(str) == response
  end

  test "`:ssh_connection.exec` failure" do
    assert SSHEx.run(:mocked, ~c"somecommand", connection_module: ExecFailureMock) ==
             {:error, "Could not exec 'somecommand'!"}

    str = SSHEx.stream(:mocked, ~c"somecommand", connection_module: ExecFailureMock)
    assert Enum.to_list(str) == [error: "Could not exec 'somecommand'!"]

    assert_raise RuntimeError, "{:error, \"Could not exec 'somecommand'!\"}", fn ->
      SSHEx.cmd!(:mocked, ~c"somecommand", connection_module: ExecFailureMock)
    end
  end

  test "`:ssh_connection.exec` error" do
    assert SSHEx.run(:mocked, ~c"somecommand", connection_module: ExecErrorMock) ==
             {:error, :reason}

    str = SSHEx.stream(:mocked, ~c"somecommand", connection_module: ExecErrorMock)
    assert Enum.to_list(str) == [error: :reason]

    assert_raise RuntimeError, "{:error, :reason}", fn ->
      SSHEx.cmd!(:mocked, ~c"somecommand", connection_module: ExecErrorMock)
    end
  end

  test "`:ssh_connection.session_channel` error" do
    assert SSHEx.run(:mocked, ~c"somecommand", connection_module: SessionChannelErrorMock) ==
             {:error, :reason}

    str = SSHEx.stream(:mocked, ~c"somecommand", connection_module: SessionChannelErrorMock)
    assert Enum.to_list(str) == [error: :reason]

    assert_raise RuntimeError, "{:error, :reason}", fn ->
      SSHEx.cmd!(:mocked, ~c"somecommand", connection_module: SessionChannelErrorMock)
    end
  end

  test "receive only from given connection" do
    # send mocked response sequence to the mailbox for 2 different connections
    # any would do
    status = 123
    mocked_data1 = "output1"
    send_regular_sequence(mocked_data1, status, conn: :mocked1)
    mocked_data2 = "output2"
    send_regular_sequence(mocked_data2, status, conn: :mocked2)

    # check that we only receive for the one we want
    assert SSHEx.cmd!(:mocked2, ~c"somecommand", connection_module: AllOKMock) == mocked_data2
  end

  defp send_long_sequence(lines, opts \\ []) do
    for l <- lines do
      send(self(), {:ssh_cm, :mocked, {:data, :mocked, 0, l}})
    end

    if opts[:error], do: send(self(), {:ssh_cm, :mocked, {:error, :reason}})

    send(self(), {:ssh_cm, :mocked, {:data, :mocked, 1, "mockederror"}})
    send(self(), {:ssh_cm, :mocked, {:eof, :mocked}})
    send(self(), {:ssh_cm, :mocked, {:exit_status, :mocked, 0}})
    send(self(), {:ssh_cm, :mocked, {:closed, :mocked}})
  end

  defp send_regular_sequence(mocked_data, status, opts \\ []) do
    conn = opts[:conn] || :mocked
    send(self(), {:ssh_cm, conn, {:data, conn, 0, mocked_data}})
    send(self(), {:ssh_cm, conn, {:eof, conn}})
    send(self(), {:ssh_cm, conn, {:exit_status, conn, status}})
    send(self(), {:ssh_cm, conn, {:closed, conn}})
  end

  defp send_separated_sequence(mocked_stdout, mocked_stderr) do
    send(self(), {:ssh_cm, :mocked, {:data, :mocked, 0, mocked_stdout}})
    send(self(), {:ssh_cm, :mocked, {:data, :mocked, 1, mocked_stderr}})
    send(self(), {:ssh_cm, :mocked, {:eof, :mocked}})
    send(self(), {:ssh_cm, :mocked, {:exit_status, :mocked, 2}})
    send(self(), {:ssh_cm, :mocked, {:closed, :mocked}})
  end
end

defmodule AllOKMock do
  def connect(_, _, _, _), do: {:ok, :mocked}
  def session_channel(conn, _), do: {:ok, conn}
  def exec(_, _, _, _), do: :success
  def adjust_window(_, _, _), do: :ok
  def close(_, _), do: :ok
end

defmodule ExecFailureMock do
  def session_channel(_, _), do: {:ok, :mocked}
  def exec(_, _, _, _), do: :failure
  def adjust_window(_, _, _), do: :ok
  def close(_, _), do: :ok
end

defmodule ExecErrorMock do
  def session_channel(_, _), do: {:ok, :mocked}
  def exec(_, _, _, _), do: {:error, :reason}
  def adjust_window(_, _, _), do: :ok
  def close(_, _), do: :ok
end

defmodule SessionChannelErrorMock do
  def session_channel(_, _), do: {:error, :reason}
  def exec(_, _, _, _), do: :success
  def adjust_window(_, _, _), do: :ok
  def close(_, _), do: :ok
end
