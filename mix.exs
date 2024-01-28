defmodule SSHEx.Mixfile do
  use Mix.Project

  @version "2.2.1"

  def project do
    [
      app: :sshex,
      version: @version,
      elixir: "~> 1.14",
      package: package(),
      deps: deps(),
      docs: docs(),
      description: "Simple SSH helpers for Elixir"
    ]
  end

  def application do
    [extra_applications: [:ssh]]
  end

  defp package do
    [
      maintainers: ["Niklas Johansson"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/witchtails/sshex"}
    ]
  end

  defp docs do
    [
      main: "SSHEx",
      source_ref: "v#{@version}",
      source_url: "https://github.com/witchtails/sshex"
    ]
  end

  defp deps, do: [{:ex_doc, ">= 0.0.0", only: :dev}]
end
