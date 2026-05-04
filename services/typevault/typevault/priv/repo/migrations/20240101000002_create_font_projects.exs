defmodule TypeVault.Repo.Migrations.CreateFontProjects do
  use Ecto.Migration

  def change do
    create table(:font_projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :design_notes, :text
      add :is_public, :boolean, null: false, default: false
      add :downloads, :integer, null: false, default: 0
      add :rating, :float, null: false, default: 0.0
      add :tags, {:array, :string}, null: false, default: []
      add :license, :string, null: false, default: "proprietary"
      add :preview_text, :string, default: "The quick brown fox jumps over the lazy dog"

      timestamps(type: :utc_datetime)
    end

    create index(:font_projects, [:user_id])
    create index(:font_projects, [:is_public])
    create index(:font_projects, [:inserted_at])
    create index(:font_projects, [:downloads])
    create index(:font_projects, [:rating])
  end
end
