defmodule SSHExTest do
  use ExUnit.Case

  test "Plain `cmd!`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    status = 123 # any would do
    send_regular_sequence mocked_data, status

    # actually test it
    assert SSHEx.cmd!(:mocked, 'somecommand', 5000, 5000, connection_module: AllOKMock) == mocked_data
  end

  test "Plain `run`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    status = 123 # any would do
    send_regular_sequence mocked_data, status

    assert SSHEx.run(:mocked, 'somecommand', 5000, 5000, connection_module: AllOKMock) == {:ok, mocked_data, status}
  end

  test "`:ssh` error message when `run`" do
    send self(), {:ssh_cm, :mocked, {:error, :reason}}
    assert_raise RuntimeError, "{:error, :reason}", fn ->
      SSHEx.run(:mocked, 'somecommand', 5000, 5000, connection_module: AllOKMock)
    end
  end

  test "`:ssh` error message when `cmd!`" do
    send self(), {:ssh_cm, :mocked, {:error, :reason}}
    assert_raise RuntimeError, "{:error, :reason}", fn ->
      SSHEx.cmd!(:mocked, 'somecommand', 5000, 5000, connection_module: AllOKMock)
    end
  end

  test "`:ssh_connection.exec` failure raises" do
    assert_raise RuntimeError, "Could not exec 'somecommand'!", fn ->
      SSHEx.run(:mocked, 'somecommand', 5000, 5000, connection_module: ExecFailureMock)
    end
  end

  test "`:ssh_connection.exec` error raises" do
    assert_raise RuntimeError, "{:error, :reason}", fn ->
      SSHEx.run(:mocked, 'somecommand', 5000, 5000, connection_module: ExecErrorMock)
    end
  end

  test "`:ssh_connection.session_channel` error raises" do
    assert_raise RuntimeError, "{:error, :reason}", fn ->
      SSHEx.run(:mocked, 'somecommand', 5000, 5000, connection_module: SessionChannelErrorMock)
    end
  end

  test "Separate streams" do
    # send mocked response sequence to the mailbox
    mocked_stdout = "output"
    mocked_stderr = "something failed"
    send_separated_sequence mocked_stdout, mocked_stderr

    # actually test it
    res = SSHEx.run :mocked, 'failingcommand',
                      5000, 5000, [connection_module: AllOKMock, separate_streams: true]
    assert res == {:ok, mocked_stdout, mocked_stderr, 2}
  end

  test "Stream long response" do
    lines = ["some", "long", "output", "sequence"]
    send_long_sequence(lines)
    response = Enum.map(lines,&( {:stdout,&1} )) ++ [
      {:stderr,"mockederror"},
      {:status, 0}
    ]

    stream = SSHEx.stream :mocked, 'somecommand', connection_module: AllOKMock
    assert Enum.to_list(stream) == response
  end

  defp send_long_sequence(lines) do
    for l <- lines do
      send self(), {:ssh_cm, :mocked, {:data, :mocked, 0, l}}
    end
    send self(), {:ssh_cm, :mocked, {:data, :mocked, 1, "mockederror"}}
    send self(), {:ssh_cm, :mocked, {:eof, :mocked}}
    send self(), {:ssh_cm, :mocked, {:exit_status, :mocked, 0}}
    send self(), {:ssh_cm, :mocked, {:closed, :mocked}}
  end

  defp send_regular_sequence(mocked_data, status) do
    send self(), {:ssh_cm, :mocked, {:data, :mocked, 0, mocked_data}}
    send self(), {:ssh_cm, :mocked, {:eof, :mocked}}
    send self(), {:ssh_cm, :mocked, {:exit_status, :mocked, status}}
    send self(), {:ssh_cm, :mocked, {:closed, :mocked}}
  end

  defp send_separated_sequence(mocked_stdout, mocked_stderr) do
    send self(), {:ssh_cm, :mocked, {:data, :mocked, 0, mocked_stdout}}
    send self(), {:ssh_cm, :mocked, {:data, :mocked, 1, mocked_stderr}}
    send self(), {:ssh_cm, :mocked, {:eof, :mocked}}
    send self(), {:ssh_cm, :mocked, {:exit_status, :mocked, 2}}
    send self(), {:ssh_cm, :mocked, {:closed, :mocked}}
  end

end

defmodule AllOKMock do
  def session_channel(_,_), do: {:ok, :mocked}
  def exec(_,_,_,_), do: :success
end

defmodule ExecFailureMock do
  def session_channel(_,_), do: {:ok, :mocked}
  def exec(_,_,_,_), do: :failure
end

defmodule ExecErrorMock do
  def session_channel(_,_), do: {:ok, :mocked}
  def exec(_,_,_,_), do: {:error, :reason}
end

defmodule SessionChannelErrorMock do
  def session_channel(_,_), do: {:error, :reason}
  def exec(_,_,_,_), do: :success
end
