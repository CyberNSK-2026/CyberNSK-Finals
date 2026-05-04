defmodule TypeVault.ExportPreset do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "export_presets" do
    field :name, :string
    field :description, :string
    field :settings, :map, default: %{}
    field :is_default, :boolean, default: false

    belongs_to :user, TypeVault.Accounts.User

    timestamps()
  end

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, [:name, :description, :settings, :is_default])
    |> validate_required([:name, :settings])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_settings()
    |> unique_constraint([:user_id, :name])
  end

  defp validate_settings(changeset) do
    case get_field(changeset, :settings) do
      nil -> changeset
      settings when is_map(settings) -> changeset
      _ -> add_error(changeset, :settings, "must be a JSON object")
    end
  end
end
