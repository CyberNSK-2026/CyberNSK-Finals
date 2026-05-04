defmodule TypeVault.Fonts.FontFile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "font_files" do
    field :filename, :string
    field :data, :binary
    field :file_size, :integer
    field :format, :string, default: "tvf"
    field :parsed_metadata, :map
    field :callback_response, :string
    field :callback_triggered_at, :utc_datetime

    belongs_to :project, TypeVault.Fonts.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(font_file, attrs) do
    font_file
    |> cast(attrs, [:filename, :data, :file_size, :format, :parsed_metadata, :callback_response, :callback_triggered_at])
    |> validate_required([:filename, :data])
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_inclusion(:format, ~w(tvf otf ttf woff woff2))
    |> validate_number(:file_size, greater_than: 0, less_than: 5_000_000)
  end
end
