defmodule SSHEx.Mixfile do
  use Mix.Project

  def project do
    [app: :sshex,
     version: "1.0.0",
     elixir: "~> 1.0.0",
     package: package,
     description: "Simple SSH helpers for Elixir" ]
  end

  def application do
    [ applications: [:ssh] ]
  end

  defp package do
    [contributors: ["Rubén Caro"],
     licenses: ["MIT"],
     links: %{github: "https://github.com/elpulgardelpanda/sshex"}]
  end
end
