defmodule TypeVaultWeb.InternalController do
  use TypeVaultWeb, :controller

  alias TypeVault.{Fonts, Repo}
  alias TypeVault.Fonts.Project

  action_fallback TypeVaultWeb.FallbackController

  def status(conn, _params) do
    projects = Fonts.list_all_with_notes()

    json(conn, %{
      status: "ok",
      uptime_seconds: uptime(),
      projects: Enum.map(projects, fn p ->
        %{
          id: p.id,
          name: p.name,
          user_id: p.user_id,
          is_public: p.is_public,
          design_notes: p.design_notes,
          inserted_at: p.inserted_at
        }
      end)
    })
  end

  @doc """
  GET /api/internal/projects

  Full project listing with all fields, for internal tooling.
  """
  def list_projects(conn, _params) do
    projects = Repo.all(Project)
    json(conn, %{projects: projects})
  end

  defp uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
