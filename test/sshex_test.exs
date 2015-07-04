defmodule SSHExTest do
  use ExUnit.Case

  setup do
    # proper connection mocks
    :meck.new(:ssh_connection)
    :meck.expect(:ssh_connection, :session_channel, fn(_,_) -> {:ok, :mocked} end)
    :meck.expect(:ssh_connection, :exec, fn(_,_,_,_) -> :success end)

    # clean them on exit
    on_exit fn -> :meck.unload end
  end

  test "Plain `cmd!`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    status = 123 # any would do
    send_regular_sequence mocked_data, status

    # actually test it
    assert SSHEx.cmd!(:mocked, 'somecommand') == mocked_data
  end

  test "Plain `run`" do
    # send mocked response sequence to the mailbox
    mocked_data = "output"
    status = 123 # any would do
    send_regular_sequence mocked_data, status

    assert SSHEx.run(:mocked, 'somecommand') == {:ok, mocked_data, status}
  end

  test "Separate streams" do
    # send mocked response sequence to the mailbox
    mocked_stdout = "output"
    mocked_stderr = "something failed"
    send_separated_sequence mocked_stdout, mocked_stderr

    # actually test it
    res = SSHEx.run :mocked, 'failingcommand',
                      5000, 5000, [separate_streams: true]
    assert res == {:ok, mocked_stdout, mocked_stderr, 2}
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
