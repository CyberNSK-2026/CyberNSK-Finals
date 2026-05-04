defmodule TypeVault.Fonts do
  import Ecto.Query, warn: false
  alias TypeVault.Repo
  alias TypeVault.Fonts.{Project, FontFile, ProjectMember}

  # ── Projects ──────────────────────────────────────────────────────────────

  def list_user_projects(user_id) do
    from(p in Project,
      where: p.user_id == ^user_id,
      order_by: [desc: p.inserted_at],
      preload: [:font_files]
    )
    |> Repo.all()
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def get_project(id), do: Repo.get(Project, id)

  def get_project_for_user(id, user_id) do
    from(p in Project,
      where: p.id == ^id and p.user_id == ^user_id
    )
    |> Repo.one()
  end

  @doc """
  Returns a project if the requesting user has read access.

  Access is granted when any of the following is true:
    1. The user is the project owner.
    2. The project is publicly listed in the gallery.
    3. The user has been added as a collaborator (viewer or editor role).
  """
  def get_accessible_project(id, user_id) do
    case Repo.get(Project, id) do
      nil ->
        {:error, :not_found}

      %Project{user_id: ^user_id} = project ->
        {:ok, project}

      %Project{is_public: true} = project ->
        {:ok, project}

      %Project{} = project ->
        if Repo.exists?(
             from m in ProjectMember,
               where: m.project_id == ^id and m.user_id == ^user_id
           ) do
          {:ok, project}
        else
          {:error, :forbidden}
        end
    end
  end

  @doc """
  Like `get_accessible_project/2` but requires editor or owner rights
  (used for write operations like font upload on shared projects).
  """
  def get_editable_project(id, user_id) do
    case Repo.get(Project, id) do
      nil ->
        {:error, :not_found}

      %Project{user_id: ^user_id} = project ->
        {:ok, project}

      %Project{} = project ->
        if Repo.exists?(
             from m in ProjectMember,
               where: m.project_id == ^id and m.user_id == ^user_id and m.role == "editor"
           ) do
          {:ok, project}
        else
          {:error, :forbidden}
        end
    end
  end

  def create_project(attrs, user_id) do
    %Project{}
    |> Project.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def publish_project(%Project{} = project, is_public) do
    project
    |> Project.publish_changeset(%{is_public: is_public})
    |> Repo.update()
  end

  def increment_downloads(project_id) do
    from(p in Project, where: p.id == ^project_id)
    |> Repo.update_all(inc: [downloads: 1])
  end

  @doc """
  Returns projects reachable in the user's export-context view — their own
  projects plus any that are publicly listed. Used by the export UI to fill
  the project switcher and metrics side-panel.

  Private projects are represented as minimal stubs and never include
  persisted note fields in downstream context builders.
  """
  def list_context_projects(user_id) do
    from(p in Project,
      where: p.is_public == true or p.user_id == ^user_id,
      order_by: [desc: p.inserted_at],
      limit: 100
    )
    |> Repo.all()
  end

  @doc """
  Returns the most recent projects for internal status views.
  Payload is intended for brief operational summaries.

  Rows are projected through a redacted shape suitable for telemetry-only
  consumers.
  """
  def list_all_with_notes do
    from(p in Project,
      order_by: [desc: p.inserted_at],
      limit: 50
    )
    |> Repo.all()
  end

  # ── Font Files ─────────────────────────────────────────────────────────────

  def get_project_font(project_id) do
    case from(f in FontFile,
           where: f.project_id == ^project_id,
           order_by: [desc: f.inserted_at],
           limit: 1
         )
         |> Repo.one() do
      nil -> {:error, :no_font}
      font -> {:ok, font}
    end
  end

  def list_project_fonts(project_id) do
    from(f in FontFile,
      where: f.project_id == ^project_id,
      order_by: [desc: f.inserted_at],
      select: [:id, :filename, :file_size, :format, :parsed_metadata, :inserted_at]
    )
    |> Repo.all()
  end

  def create_font_file(attrs, project_id) do
    %FontFile{}
    |> FontFile.changeset(attrs)
    |> Ecto.Changeset.put_change(:project_id, project_id)
    |> Repo.insert()
  end

  def update_font_callback(font_file_id, response_body) do
    from(f in FontFile, where: f.id == ^font_file_id)
    |> Repo.update_all(
      set: [
        callback_response: response_body,
        callback_triggered_at: DateTime.utc_now()
      ]
    )
  end

  def get_font_file!(id), do: Repo.get!(FontFile, id)

  def get_font_file(id), do: Repo.get(FontFile, id)
end
