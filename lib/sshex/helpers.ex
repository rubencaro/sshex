defmodule SSHEx.Helpers do
  @moduledoc """
    require SSHEx.Helpers, as: H  # the cool way
  """
  @doc """
    Convenience to get environment bits. Avoid all that repetitive
    `Application.get_env( :myapp, :blah, :blah)` noise.
  """
  def env(key, default \\ nil), do: env(Mix.Project.get!().project[:app], key, default)
  def env(app, key, default), do: Application.get_env(app, key, default)

  @doc """
  Spit to output any passed variable, with location information.
  If `sample` option is given, it should be a float between 0.0 and 1.0.
  Output will be produced randomly with that probability.
  Given `opts` will be fed straight into `inspect`. Any option accepted by it should work.
  """
  defmacro spit(obj \\ "", opts \\ []) do
    quote do
      opts = unquote(opts)
      obj = unquote(obj)
      opts = Keyword.put(opts, :env, __ENV__)

      SSHEx.Helpers.maybe_spit(obj, opts, opts[:sample])
      # chainable
      obj
    end
  end

  @doc false
  def maybe_spit(obj, opts, nil), do: do_spit(obj, opts)

  def maybe_spit(obj, opts, prob) when is_float(prob) do
    if :rand.uniform() <= prob, do: do_spit(obj, opts)
  end

  defp do_spit(obj, opts) do
    %{file: file, line: line} = opts[:env]
    name = Process.info(self())[:registered_name]

    chain = [
      :bright,
      :red,
      "\n\n#{file}:#{line}",
      :normal,
      "\n     #{inspect(self())}",
      :green,
      " #{name}"
    ]

    msg = inspect(obj, opts)
    chain = chain ++ [:red, "\n\n#{msg}"]

    (chain ++ ["\n\n", :reset]) |> IO.ANSI.format(true) |> IO.puts()
  end

  @doc """
    Print to stdout a _TODO_ message, with location information.
  """
  defmacro todo(msg \\ "") do
    quote do
      %{file: file, line: line} = __ENV__

      [:yellow, "\nTODO: #{file}:#{line} #{unquote(msg)}\n", :reset]
      |> IO.ANSI.format(true)
      |> IO.puts()

      :todo
    end
  end

  @doc """
    Apply given defaults to given Keyword. Returns merged Keyword.

    The inverse of `Keyword.merge`, best suited to apply some defaults in a
    chainable way.

    Ex:
      kw = gather_data
        |> transform_data
        |> H.defaults(k1: 1234, k2: 5768)
        |> here_i_need_defaults

    Instead of:
      kw1 = gather_data
        |> transform_data
      kw = [k1: 1234, k2: 5768]
        |> Keyword.merge(kw1)
        |> here_i_need_defaults

  """
  def defaults(args, defs) do
    defs |> Keyword.merge(args)
  end

  def convert_values(args) do
    Enum.map(args, fn {k, v} -> {k, convert_value(v)} end)
  end

  def convert_value(v) when is_binary(v) do
    String.to_charlist(v)
  end

  def convert_value(v), do: v
end
