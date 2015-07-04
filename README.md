# SSHEx
[![Build Status](https://travis-ci.org/rubencaro/sshex.svg?branch=master)](https://travis-ci.org/rubencaro/sshex)
[![Hex Version](http://img.shields.io/hexpm/v/sshex.svg?style=flat)](https://hex.pm/packages/sshex)

Simple SSH helpers for Elixir.

Library to unify helpers already used on several applications. It uses low level
Erlang [ssh library](http://www.erlang.org/doc/man/ssh.html).

The only purpose of these helpers is to avoid repetitive patterns seen when
working with SSH from Elixir. It doesn't mean to hide anything from the
venerable code underneath. If there's an ugly crash from `:ssh`, it will
raise freely.

## Use

Just add `{:sshex, "1.1.0"}` to your deps on `mix.exs`.

Then assuming `:ssh` application is already started (hence it is listed on deps),
you should acquire an SSH connection using `:ssh.connect/4` like this:

```elixir
    {:ok, conn} = :ssh.connect('123.123.123.123', 22,
                    [ {:user,'myuser'}, {:silently_accept_hosts, true} ], 5000)
```

Then you can use the acquired `conn` with the `cmd!/4` helper like this:

```elixir
    SSHEx.cmd! conn, 'mkdir -p /path/to/newdir'
    res = SSHEx.cmd! conn, 'ls /some/path'
```

This is meant to run commands which you don't care about the return code.
`cmd!/4` will return the output of the command only. If you want to check the
status code too, you can use `run/4` like this:

```elixir
    {:ok, _, 0} = SSHEx.run conn, 'rm -fr /something/to/delete'
    {:ok, res, 0} = SSHEx.run conn, 'ls /some/path'
```

You can pass the option `:separate_streams` to get separated stdout and stderr.
Like this:

```elixir
    {:ok, stdout, stderr, 2} = SSHEx.run conn, 'ls /nonexisting/path',
                                     5000, 5000, [separate_streams: true]
```

You will be reusing the same SSH connection all over.


## Alternative keys

To use alternative keys you should save them somewhere on disk and then set
the `:user_dir` option for `:ssh.connect/4`. See
[ssh library docs](http://www.erlang.org/doc/man/ssh.html) for more options.


## TODOs

* Put every optional parameter under a unique Keyword list
* Add tunnelling helpers [*](http://erlang.org/pipermail/erlang-questions/2014-June/079481.html)

## Changelog

### 1.1

* Add support for separate stdout/stderr responses.

### 1.0

* Initial release
