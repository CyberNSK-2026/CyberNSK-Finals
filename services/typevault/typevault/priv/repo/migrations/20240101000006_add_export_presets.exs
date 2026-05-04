defmodule TypeVault.Repo.Migrations.AddExportPresets do
  use Ecto.Migration

  def change do
    create table(:export_presets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :string
      # JSON object: format, quality, width, height, background, sample_text, etc.
      add :settings, :map, null: false, default: %{}
      add :is_default, :boolean, null: false, default: false

      timestamps()
    end

    create index(:export_presets, [:user_id])
    create unique_index(:export_presets, [:user_id, :name])
  end
end
