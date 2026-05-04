defmodule TypeVaultWeb.AuthController do
  use TypeVaultWeb, :controller

  alias TypeVault.Accounts
  alias TypeVault.Guardian

  action_fallback TypeVaultWeb.FallbackController

  def register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params),
         {:ok, token, _claims} <- Guardian.encode_and_sign(user) do
      conn
      |> put_status(:created)
      |> json(%{
        user: user_json(user),
        token: token
      })
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, token, _claims} <- Guardian.encode_and_sign(user) do
      json(conn, %{
        user: user_json(user),
        token: token
      })
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email and password required"})
  end

  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{user: user_json(user)})
  end

  def update_profile(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, updated_user} <- Accounts.update_user(user, params) do
      json(conn, %{user: user_json(updated_user)})
    end
  end

  defp user_json(user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      bio: user.bio,
      website: user.website,
      avatar_url: user.avatar_url,
      role: user.role,
      inserted_at: user.inserted_at
    }
  end
end
