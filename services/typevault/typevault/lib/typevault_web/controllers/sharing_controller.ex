defmodule TypeVaultWeb.SharingController do
  use TypeVaultWeb, :controller

  alias TypeVault.{Fonts, Sharing, Events, Guardian}

  action_fallback TypeVaultWeb.FallbackController

  @doc """
  GET /api/projects/:project_id/members

  Lists all collaborators on a project.
  Only the project owner or existing members can view the member list.
  """
  def index(conn, %{"project_id" => project_id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, _project} <- Fonts.get_accessible_project(project_id, user.id) do
      members = Sharing.list_members(project_id)
      json(conn, %{members: Enum.map(members, &member_json/1)})
    end
  end

  @doc """
  POST /api/projects/:project_id/members

  Invites a collaborator by email.

  Body:
    email  – email address of the user to invite
    role   – "viewer" (default) or "editor"

  Only the project owner can manage members.
  """
  def create(conn, %{"project_id" => project_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    email = Map.get(params, "email", "")
    role = Map.get(params, "role", "viewer")

    with project when not is_nil(project) <- Fonts.get_project_for_user(project_id, user.id) ||
                                               {:error, :forbidden},
         {:ok, member} <- Sharing.add_member(project_id, email, role) do
      Events.log(project_id, user.id, "shared", %{
        invited_email: email,
        role: role
      })

      conn
      |> put_status(:created)
      |> json(%{member: member_json(member)})
    else
      {:error, :user_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "no user with that email"})

      {:error, :already_member} ->
        conn |> put_status(:conflict) |> json(%{error: "user is already a collaborator"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "only the project owner can manage members"})

      nil ->
        conn |> put_status(:forbidden) |> json(%{error: "only the project owner can manage members"})

      error ->
        error
    end
  end

  @doc """
  PUT /api/projects/:project_id/members/:user_id

  Updates a collaborator's role.
  """
  def update(conn, %{"project_id" => project_id, "user_id" => target_user_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    role = Map.get(params, "role", "viewer")

    with project when not is_nil(project) <- Fonts.get_project_for_user(project_id, user.id),
         member when not is_nil(member) <- Sharing.get_member(project_id, target_user_id),
         {:ok, updated} <- Sharing.update_member_role(member, role) do
      json(conn, %{member: member_json(updated)})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  DELETE /api/projects/:project_id/members/:user_id

  Removes a collaborator from the project.
  """
  def delete(conn, %{"project_id" => project_id, "user_id" => target_user_id}) do
    user = Guardian.Plug.current_resource(conn)

    with project when not is_nil(project) <- Fonts.get_project_for_user(project_id, user.id),
         {:ok, _} <- Sharing.remove_member(project_id, target_user_id) do
      Events.log(project_id, user.id, "member_removed", %{removed_user_id: target_user_id})
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp member_json(%{user: user} = member) when not is_nil(user) do
    %{
      id: member.id,
      role: member.role,
      inserted_at: member.inserted_at,
      user: %{
        id: user.id,
        username: user.username,
        email: user.email
      }
    }
  end

  defp member_json(member) do
    %{
      id: member.id,
      role: member.role,
      user_id: member.user_id,
      inserted_at: member.inserted_at
    }
  end
end
