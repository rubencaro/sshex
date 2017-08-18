# SSHEx
[![Build Status](https://travis-ci.org/rubencaro/sshex.svg?branch=master)](https://travis-ci.org/rubencaro/sshex)
[![Hex Version](http://img.shields.io/hexpm/v/sshex.svg?style=flat)](https://hex.pm/packages/sshex)
[![Hex Version](http://img.shields.io/hexpm/dt/sshex.svg?style=flat)](https://hex.pm/packages/sshex)

Simple SSH helpers for Elixir.

Library to unify helpers already used on several applications. It uses low level Erlang [ssh library](http://www.erlang.org/doc/man/ssh.html).

The only purpose of these helpers is to avoid repetitive patterns seen when working with SSH from Elixir. It doesn't mean to hide anything from the venerable code underneath. If there's an ugly crash from `:ssh` it will come back as `{:error, reason}`.

## Installation

Just add `{:sshex, "2.2.0"}` to your deps on `mix.exs` and run `mix deps.get`

## Use

Then assuming `:ssh` application is already started with `:ssh.start` (hence it is listed on deps), you should acquire an SSH connection using `SSHEx.connect/1` like this:

1.You can use `ssh-copy-id myuser@123.123.123.123.123` to copy ssh key to remote host and then connect using this line:
```elixir
{:ok, conn} = SSHEx.connect ip: '123.123.123.123', user: 'myuser'
```
2.You can supply the password:
```elixir
{:ok, conn} = SSHEx.connect ip: '123.123.123.123', user: 'myuser', password: 'your-password'
```

Then you can use the acquired `conn` with the `cmd!/4` helper like this:

```elixir
SSHEx.cmd! conn, 'mkdir -p /path/to/newdir'
res = SSHEx.cmd! conn, 'ls /some/path'
```

This is meant to run commands which you don't care about the return code. `cmd!/3` will return the output of the command only, and __will raise any errors__. If you want to check the status code, and control errors too, you can use `run/3` like this:

```elixir
{:ok, _, 0} = SSHEx.run conn, 'rm -fr /something/to/delete'
{:ok, res, 0} = SSHEx.run conn, 'ls /some/path'
{:error, reason} = SSHEx.run failing_conn, 'ls /some/path'
```

You can pass the option `:separate_streams` to get separated stdout and stderr. Like this:

```elixir
{:ok, stdout, stderr, 2} = SSHEx.run conn, 'ls /nonexisting/path', separate_streams: true
```

You will be reusing the same SSH connection all over.


## Streaming

You can use `SSHEx` to run some command and create a [`Stream`](http://elixir-lang.org/docs/stable/elixir/Stream.html), so you can lazily process an arbitrarily long output as it arrives. Internally `Stream.resource/3` is used to create the `Stream`, and every response from `:ssh` is emitted so it can be easily matched with a simple `case`.

You just have to use `stream/3` like this:

```elixir
str = SSHEx.stream conn, 'somecommand'

Enum.each(str, fn(x)->
  case x do
    {:stdout,row}    -> process_stdout(row)
    {:stderr,row}    -> process_stderr(row)
    {:status,status} -> process_exit_status(status)
    {:error,reason}  -> process_error(reason)
  end
end)
```

## Alternative keys

To use alternative keys you should save them somewhere on disk and then set the `:user_dir` option for `SSHEx.connect/4`. See [ssh library docs](http://www.erlang.org/doc/man/ssh.html) for more options.


## TODOs

* Add tunnelling helpers [*](http://erlang.org/pipermail/erlang-questions/2014-June/079481.html)

## Changelog

### 2.2.0

* Add ability to specify ssh key and known hosts
* Make it Elixir string friendly

### 2.1.2

* Remove Elixir 1.4 warnings

### 2.1.1

* Close channel after stream

### 2.1.0

* Add `connect/1` to improve testability by easier mocking

### 2.0.1

* Avoid some Elixir 1.2.0 warnings
* Adjust the SSH flow control window to handle long outputs (fixes #4).

### 2.0.0

Backwards incompatible changes:
* Remove every `raise`, get clean controlled `{:error, reason}` responses
* Put every optional parameter under a unique Keyword list

### 1.3.1

* Fix Elixir version requested. Use >= 1.0 now.

### 1.3

* Support streaming via `stream/3`
* Stop using global mocks (i.e. `:meck`)

### 1.2

* Uniform `raise` behaviour on `:ssh` errors.
* Document and test `:ssh` error handling

### 1.1

* Add support for separate stdout/stderr responses.

### 1.0

* Initial release
