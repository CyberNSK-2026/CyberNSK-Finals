defmodule TypeVaultWeb.ActivityController do
  use TypeVaultWeb, :controller

  alias TypeVault.{Fonts, Events, Guardian}
  alias TypeVaultWeb.Helpers.Pagination

  action_fallback TypeVaultWeb.FallbackController

  @doc """
  GET /api/projects/:project_id/activity

  Returns a paginated, searchable activity feed for a project.

  Query params:
    limit   – max events per page (default 30, max 100)
    offset  – pagination offset
    search  – filter by event_type substring (e.g. "export", "upload")
  """
  def index(conn, %{"project_id" => project_id} = params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, _project} <- Fonts.get_accessible_project(project_id, user.id) do
      %{limit: limit, offset: offset} = Pagination.parse_pagination(params, 30)
      search = Map.get(params, "search", "")

      events = Events.list_events(project_id, limit: limit, offset: offset, search: search)
      total = Events.count_events(project_id, search)

      result = Pagination.paginate(Enum.map(events, &event_json/1), total, %{
        limit: limit,
        offset: offset
      })

      json(conn, result)
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp event_json(event) do
    %{
      id: event.id,
      event_type: event.event_type,
      payload: event.payload,
      inserted_at: event.inserted_at,
      actor: actor_json(event.actor)
    }
  end

  defp actor_json(nil), do: nil

  defp actor_json(user) do
    %{id: user.id, username: user.username}
  end
end
