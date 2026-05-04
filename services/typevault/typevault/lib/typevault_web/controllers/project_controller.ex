defmodule TypeVaultWeb.ProjectController do
  use TypeVaultWeb, :controller

  alias TypeVault.Fonts
  alias TypeVault.Guardian

  action_fallback TypeVaultWeb.FallbackController

  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    projects = Fonts.list_user_projects(user.id)
    json(conn, %{projects: Enum.map(projects, &project_json/1)})
  end

  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, project} <- Fonts.create_project(params, user.id) do
      conn
      |> put_status(:created)
      |> json(%{project: project_json(project)})
    end
  end

  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, project} <- Fonts.get_accessible_project(id, user.id) do
      json(conn, %{project: project_full_json(project, user)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    with project when not is_nil(project) <- Fonts.get_project_for_user(id, user.id),
         {:ok, updated} <- Fonts.update_project(project, params) do
      json(conn, %{project: project_full_json(updated, user)})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    with project when not is_nil(project) <- Fonts.get_project_for_user(id, user.id),
         {:ok, _} <- Fonts.delete_project(project) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def publish(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    is_public = Map.get(params, "is_public", false)

    with project when not is_nil(project) <- Fonts.get_project_for_user(id, user.id),
         {:ok, updated} <- Fonts.publish_project(project, is_public) do
      json(conn, %{project: project_json(updated), message: "visibility updated"})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  # ── JSON helpers ───────────────────────────────────────────────────────────

  # Public view — no design_notes
  defp project_json(p) do
    %{
      id: p.id,
      name: p.name,
      description: p.description,
      is_public: p.is_public,
      downloads: p.downloads,
      rating: p.rating,
      tags: p.tags,
      license: p.license,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end

  # Full view — includes design_notes for the project owner
  defp project_full_json(p, user) do
    base = project_json(p)

    if p.user_id == user.id do
      Map.put(base, :design_notes, p.design_notes)
    else
      base
    end
  end
end
