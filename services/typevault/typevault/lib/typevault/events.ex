defmodule TypeVault.Events do
  @moduledoc """
  Project activity feed and audit log.

  All significant actions on a project are recorded as events and can be
  retrieved via the activity API.  Events are append-only (never deleted
  individually, removed only via CASCADE when a project is deleted).
  """

  import Ecto.Query, warn: false
  alias TypeVault.Repo
  alias TypeVault.Fonts.ProjectEvent

  @default_limit 30
  @max_limit 100

  @doc """
  Records a project event.  Fire-and-forget: errors are swallowed so that
  a logging failure never blocks the primary request.
  """
  def log(project_id, actor_id \\ nil, event_type, payload \\ %{}) do
    %ProjectEvent{}
    |> ProjectEvent.changeset(%{
      project_id: project_id,
      actor_id: actor_id,
      event_type: event_type,
      payload: payload
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  @doc """
  Returns a paginated list of events for a project, newest first.

  Options:
    - `:limit`  — max events to return (default 30, max 100)
    - `:offset` — pagination offset (default 0)
    - `:search` — filter by event_type substring
  """
  def list_events(project_id, opts \\ []) do
    limit = min(Keyword.get(opts, :limit, @default_limit), @max_limit)
    offset = Keyword.get(opts, :offset, 0)
    search = Keyword.get(opts, :search, "")

    base =
      from e in ProjectEvent,
        where: e.project_id == ^project_id,
        order_by: [desc: e.inserted_at],
        preload: [:actor]

    base
    |> maybe_search_event_type(search)
    |> Repo.paginate(limit, offset)
  end

  @doc """
  Returns the total event count for a project (used for pagination meta).
  """
  def count_events(project_id, search \\ "") do
    from(e in ProjectEvent,
      where: e.project_id == ^project_id,
      select: count(e.id)
    )
    |> maybe_search_event_type(search)
    |> Repo.one()
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp maybe_search_event_type(query, ""), do: query

  defp maybe_search_event_type(query, term) do
    from e in query,
      where: ilike(e.event_type, ^"%#{term}%")
  end
end
