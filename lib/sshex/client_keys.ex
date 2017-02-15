defmodule SSHEx.ClientKeys do
  @moduledoc ~S"""
  Provides public key behavior for SSH clients
  """

  @behaviour :ssh_client_key_api

  @spec add_host_key(hostname :: charlist, key :: list, opts :: list) :: {:ok} | {:error}
  def add_host_key(hostname, key, _opts) do
    IO.puts "The authenticity of host '" <> to_string(hostname) <> "' can't be established."

    # erlang/OTP 19.2
    if Keyword.has_key?(:public_key.module_info(:exports), :ssh_hostkey_fingerprint) do
      fp = :public_key.ssh_hostkey_fingerprint(key)
      IO.puts "RSA key fingerprint is #{fp}."
    end

    with :yes <- prompt_yes_no(),
         {:ok, hosts} <- File.read(known_hosts_file()),
         IO.puts "Adding key to known_hosts file." do
      decoded = :public_key.ssh_decode(hosts, :known_hosts)
      encoded = decoded ++ [{key, [{:hostnames, [hostname]}]}]
        |> :public_key.ssh_encode(:known_hosts)
      File.write(known_hosts_file(), encoded)
    else
      :no -> {:error}
    end
  end

  @spec is_host_key(key :: charlist, hostname :: charlist, alg :: charlist, opts :: list) :: boolean
  def is_host_key(key, hostname, _alg, _opts) do
    hosts = File.read!(known_hosts_file())
    decoded = :public_key.ssh_decode(hosts, :known_hosts)
    Enum.member?(decoded, {key, [hostnames: [hostname]]})
  end

  @spec user_key(alg :: charlist, opts :: list) :: {:ok, binary()} | {:error}
  def user_key(_alg, _opts) do
    with {:ok, pem} <- File.read(identity_file()) do
      material =
        pem
        |> :public_key.pem_decode
        |> List.first
        |> :public_key.pem_entry_decode
      {:ok, material}
    else
      _ -> {:error}
    end
  end

  defp prompt_yes_no() do
    case IO.getn("Are you sure you want to continue connecting (yes/no)? ") do
      "yes" -> :yes
      "y" -> :yes
      _ -> :no
    end
  end

  defp identity_file() do
    Path.join([System.user_home!(), ".ssh", "id_rsa"])
  end

  defp known_hosts_file() do
    Path.join([System.user_home!(), ".ssh", "known_hosts"])
  end
end