defmodule TypeVault.Fonts.ProjectMember do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_roles ~w(viewer editor)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_members" do
    field :role, :string, default: "viewer"

    belongs_to :project, TypeVault.Fonts.Project
    belongs_to :user, TypeVault.Accounts.User

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:role, :project_id, :user_id])
    |> validate_required([:role, :project_id, :user_id])
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint([:project_id, :user_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:user_id)
  end
end
