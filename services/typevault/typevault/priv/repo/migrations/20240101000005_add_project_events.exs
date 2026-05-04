defmodule TypeVault.Repo.Migrations.AddProjectEvents do
  use Ecto.Migration

  def change do
    create table(:project_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:font_projects, type: :binary_id, on_delete: :delete_all),
          null: false
      # nullable — system events may have no actor
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # created | updated | published | font_uploaded | exported | shared | member_removed
      add :event_type, :string, null: false
      # arbitrary structured payload: {name: ..., changes: [...], ...}
      add :payload, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:project_events, [:project_id, :inserted_at])
    create index(:project_events, [:actor_id])
  end
end
