defmodule TypeVault.Repo.Migrations.AddProjectMembers do
  use Ecto.Migration

  def change do
    create table(:project_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:font_projects, type: :binary_id, on_delete: :delete_all),
          null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
          null: false
      # role: "viewer" — read-only; "editor" — can upload/modify fonts
      add :role, :string, null: false, default: "viewer"

      timestamps()
    end

    create unique_index(:project_members, [:project_id, :user_id])
    create index(:project_members, [:user_id])
    create index(:project_members, [:project_id])
  end
end
