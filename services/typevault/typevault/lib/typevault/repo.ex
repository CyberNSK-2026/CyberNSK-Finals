defmodule TypeVault.Repo do
  use Ecto.Repo,
    otp_app: :typevault,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query, warn: false

  @doc """
  Applies limit/offset to a query and executes it.
  Returns a list of results.
  """
  def paginate(query, limit, offset) do
    query
    |> limit(^limit)
    |> offset(^offset)
    |> __MODULE__.all()
  end
end
