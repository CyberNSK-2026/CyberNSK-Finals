defmodule TypeVault.Repo.Migrations.CreateFontFiles do
  use Ecto.Migration

  def change do
    create table(:font_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:font_projects, type: :binary_id, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :data, :binary, null: false
      add :file_size, :integer
      add :format, :string, null: false, default: "tvf"
      add :parsed_metadata, :map
      add :callback_response, :text
      add :callback_triggered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:font_files, [:project_id])
    create index(:font_files, [:inserted_at])
  end
end
