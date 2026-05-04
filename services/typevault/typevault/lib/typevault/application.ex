defmodule TypeVault.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TypeVault.Repo,
      {DNSCluster, query: Application.get_env(:typevault, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TypeVault.PubSub},
      {Finch, name: TypeVault.Finch},
      TypeVaultWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TypeVault.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TypeVaultWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
