defmodule TypeVault.Fonts.ProjectEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @event_types ~w(created updated published font_uploaded exported shared member_removed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_events" do
    field :event_type, :string
    field :payload, :map, default: %{}
    field :inserted_at, :utc_datetime_usec

    belongs_to :project, TypeVault.Fonts.Project
    belongs_to :actor, TypeVault.Accounts.User, foreign_key: :actor_id
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :payload, :project_id, :actor_id, :inserted_at])
    |> validate_required([:event_type, :project_id])
    |> validate_inclusion(:event_type, @event_types)
    |> put_inserted_at()
  end

  defp put_inserted_at(%{changes: %{inserted_at: _}} = cs), do: cs

  defp put_inserted_at(cs),
    do: put_change(cs, :inserted_at, DateTime.utc_now())
end
