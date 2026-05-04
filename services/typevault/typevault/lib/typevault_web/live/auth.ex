defmodule TypeVaultWeb.Live.Auth do
  @moduledoc "on_mount callbacks for LiveView authentication."

  import Phoenix.LiveView
  import Phoenix.Component
  alias TypeVault.Accounts

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, push_token(socket, session)}
    else
      socket =
        socket
        |> put_flash(:error, "You need to sign in to access this page.")
        |> redirect(to: "/login")
      {:halt, socket}
    end
  end

  def on_mount(:load_current_user, _params, session, socket) do
    {:cont, push_token(mount_current_user(session, socket), session)}
  end

  defp mount_current_user(session, socket) do
    case session["current_user_id"] do
      nil ->
        assign(socket, :current_user, nil)

      user_id ->
        assign_new(socket, :current_user, fn -> Accounts.get_user(user_id) end)
    end
  end

  defp push_token(socket, session) do
    case session["tv_token"] do
      nil   -> socket
      token -> push_event(socket, "set-tv-token", %{token: token})
    end
  end
end
