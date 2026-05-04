defmodule TypeVault.Fonts.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "font_projects" do
    field :name, :string
    field :description, :string
    field :design_notes, :string
    field :is_public, :boolean, default: false
    field :downloads, :integer, default: 0
    field :rating, :float, default: 0.0
    field :tags, {:array, :string}, default: []
    field :license, :string, default: "proprietary"
    field :preview_text, :string, default: "The quick brown fox jumps over the lazy dog"

    belongs_to :user, TypeVault.Accounts.User
    has_many :font_files, TypeVault.Fonts.FontFile, foreign_key: :project_id

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :design_notes, :is_public, :tags, :license, :preview_text])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 2000)
    |> validate_length(:design_notes, max: 10_000)
    |> validate_inclusion(:license, ~w(proprietary ofl apache cc-by cc-by-sa))
  end

  def publish_changeset(project, attrs) do
    project
    |> cast(attrs, [:is_public])
  end

  def stats_changeset(project, attrs) do
    project
    |> cast(attrs, [:downloads, :rating])
  end
end
