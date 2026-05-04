defmodule TypeVault.Sharing do
  @moduledoc """
  Project sharing and collaborator management.

  Supports two roles:
    - `viewer`  — read-only access (can preview, download specimens)
    - `editor`  — can upload/delete font files and update project settings
  """

  import Ecto.Query, warn: false
  alias TypeVault.Repo
  alias TypeVault.Fonts.ProjectMember
  alias TypeVault.Accounts

  @doc """
  Lists all members of a project with their user info.
  """
  def list_members(project_id) do
    from(m in ProjectMember,
      where: m.project_id == ^project_id,
      preload: [:user],
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns a member record if the user has access to the project.
  """
  def get_member(project_id, user_id) do
    Repo.get_by(ProjectMember, project_id: project_id, user_id: user_id)
  end

  @doc """
  Adds a collaborator by email address.

  Returns `{:ok, member}` or `{:error, reason}`.
  """
  def add_member(project_id, email, role) do
    with %{} = user <- Accounts.get_user_by_email(email) || {:error, :user_not_found},
         nil <- Repo.get_by(ProjectMember, project_id: project_id, user_id: user.id) ||
                  {:error, :already_member} do
      %ProjectMember{}
      |> ProjectMember.changeset(%{
        project_id: project_id,
        user_id: user.id,
        role: role
      })
      |> Repo.insert()
    else
      {:error, reason} -> {:error, reason}
      %ProjectMember{} -> {:error, :already_member}
    end
  end

  @doc """
  Updates a collaborator's role.
  """
  def update_member_role(%ProjectMember{} = member, role) do
    member
    |> ProjectMember.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a collaborator from a project.
  """
  def remove_member(project_id, user_id) do
    case Repo.get_by(ProjectMember, project_id: project_id, user_id: user_id) do
      nil -> {:error, :not_found}
      member -> Repo.delete(member)
    end
  end

  @doc """
  Returns true if the user is a member of the project (any role).
  """
  def member?(project_id, user_id) do
    Repo.exists?(
      from m in ProjectMember,
        where: m.project_id == ^project_id and m.user_id == ^user_id
    )
  end

  @doc """
  Returns true if the user has editor rights on the project.
  """
  def editor?(project_id, user_id) do
    Repo.exists?(
      from m in ProjectMember,
        where: m.project_id == ^project_id and m.user_id == ^user_id and m.role == "editor"
    )
  end
end
