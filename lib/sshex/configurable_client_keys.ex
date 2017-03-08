defmodule SSHEx.ConfigurableClientKeys do
  @moduledoc ~S"""
  Provides public key behavior for SSH clients.
  
  valid options: 
    - `key`: `IO.device` providing the ssh key (required)
    - `known_hosts`: `IO.device` providing the known hosts list (required)
    - `accept_hosts`: `boolean` silently accept and add new hosts to the known hosts. By default only known hosts will be accepted. 
  `
  SSHEx.connect(
      ip: to_charlist(hostname), 
      user: to_charlist(username), 
      key_cb: {SSHEx.ConfigurableClientKeys, [
        key: <IO.device>,
        known_hosts: <IO.device> ]}
      )
  `
  A convenience method is provided that can take filenames instead of IO devices

  `
  cb_module = SSHEx.ConfigurableClientKeys.get_cb_module(key_file: "path/to/keyfile", known_hosts_file: "path_to_known_hostsFile", accept_hosts: false)
  SSHEx.connect(
      ip: to_charlist(hostname), 
      user: to_charlist(username), 
      key_cb: cb_module
      )
  `

  """

  @behaviour :ssh_client_key_api


  @spec add_host_key(hostname :: charlist, key :: :public_key.public_key , opts :: list) :: :ok | {:error, term}
  def add_host_key(hostname, key, opts) do  
    case accept_hosts(opts) do
      true -> 
        opts
        |> known_hosts
        |> IO.read(:all)
        |> :public_key.ssh_decode(:known_hosts)
        |> (fn decoded -> decoded ++ [{key, [{:hostnames, [hostname]}]}] end).()
        |> :public_key.ssh_encode(:known_hosts)
        |> (fn encoded -> IO.write(known_hosts(opts), encoded) end).()
      _ -> 
        message = 
          """
          Error: unknown fingerprint found for #{inspect hostname} #{inspect key}.
          You either need to add a known good fingerprint to your known hosts file for this host,
          *or* pass the accept_hosts option to your client key callback
          """        
        {:error, message}
    end    
  end

  @spec is_host_key(key :: :public_key.public_key, hostname :: charlist, alg :: :ssh_client_key_api.algorithm, opts :: list) :: boolean
  def is_host_key(key, hostname, _alg, opts) do
    opts
    |> known_hosts    
    |> IO.read(:all)
    |> :public_key.ssh_decode(:known_hosts)
    |> has_fingerprint(key, hostname)
  end

  @spec user_key(alg :: :ssh_client_key_api.algorithm, opts :: list) :: {:error, term} | {:ok, :public_key.private_key}
  def user_key(_alg, opts) do
    material =
      opts
      |> key
      |> IO.read(:all)
      |> :public_key.pem_decode
      |> List.first
      |> :public_key.pem_entry_decode
    {:ok, material}
  end

  @spec get_cb_module(opts :: list) :: {atom, list}
  def get_cb_module(opts) do
    opts = 
      opts
      |> Keyword.put(:key, File.open!(opts[:key_file]))
      |> Keyword.put(:known_hosts, File.open!(opts[:known_hosts_file]))   
    {__MODULE__, opts}
  end

  @spec key(opts :: list) :: IO.device
  defp key(opts) do
    cb_opts(opts)[:key]
  end

  @spec accept_hosts(opts :: list) :: boolean
  defp accept_hosts(opts) do
    cb_opts(opts)[:accept_hosts]
  end

  @spec known_hosts(opts :: list) :: IO.device  
  defp known_hosts(opts) do
    cb_opts(opts)[:known_hosts]
  end

  @spec cb_opts(opts :: list) :: list
  defp cb_opts(opts) do
    opts[:key_cb_private]
  end

  defp has_fingerprint(fingerprints, key, hostname) do 
    Enum.any?(fingerprints, 
      fn {k, v} -> (k == key) && (Enum.member?(v[:hostnames], hostname)) end
      )
  end
end
