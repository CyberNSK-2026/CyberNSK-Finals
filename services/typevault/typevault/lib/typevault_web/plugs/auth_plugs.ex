# Loads the session user for browser/LiveView pipelines
defmodule TypeVaultWeb.Plugs.LoadSessionUser do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :current_user_id)
    user    = user_id && TypeVault.Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end
end

defmodule TypeVaultWeb.Plugs.FetchCurrentUser do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> Guardian.Plug.Pipeline.call(
      module: TypeVault.Guardian,
      error_handler: TypeVaultWeb.AuthErrorHandler
    )
    |> Guardian.Plug.VerifyHeader.call(schemes: ["Bearer"])
    |> Guardian.Plug.LoadResource.call(allow_blank: true)
  end
end

defmodule TypeVaultWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "authentication required"})
        |> halt()

      _user ->
        conn
    end
  end
end

defmodule TypeVaultWeb.Plugs.RequireLocalhost do
  @moduledoc """
  Restricts access to requests that originate from the local machine.
  Used to protect internal monitoring and maintenance endpoints.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if local_origin?(conn.remote_ip) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "forbidden"})
      |> halt()
    end
  end

  defp local_origin?({127, 0, 0, 1}),                    do: true
  defp local_origin?({0, 0, 0, 0, 0, 0, 0, 1}),         do: true
  defp local_origin?({0, 0, 0, 0, 0, 65535, 32512, 1}), do: true
  defp local_origin?(_),                                 do: false
end

defmodule TypeVaultWeb.AuthErrorHandler do
  import Plug.Conn
  import Phoenix.Controller

  def auth_error(conn, {_type, _reason}, _opts) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "invalid or expired token"})
    |> halt()
  end
end
