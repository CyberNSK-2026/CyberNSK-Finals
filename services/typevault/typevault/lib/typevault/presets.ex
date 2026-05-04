defmodule TypeVault.Presets do
  @moduledoc """
  Named export presets — reusable export configurations saved per user.

  A preset stores a JSON settings object (format, quality, dimensions,
  sample text, background colour, etc.) under a user-defined name.
  One preset per user can be marked as default and is applied automatically
  when no explicit settings are supplied to the export endpoint.
  """

  import Ecto.Query, warn: false
  alias TypeVault.Repo
  alias TypeVault.ExportPreset

  @doc "Returns all presets for a user, ordered by name."
  def list_presets(user_id) do
    from(p in ExportPreset,
      where: p.user_id == ^user_id,
      order_by: [asc: p.name]
    )
    |> Repo.all()
  end

  @doc "Returns the default preset for a user, or nil."
  def get_default_preset(user_id) do
    Repo.get_by(ExportPreset, user_id: user_id, is_default: true)
  end

  @doc "Gets a preset by id, scoped to a user."
  def get_preset(id, user_id) do
    case Repo.get(ExportPreset, id) do
      %ExportPreset{user_id: ^user_id} = p -> {:ok, p}
      %ExportPreset{} -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  @doc "Creates a new preset."
  def create_preset(attrs, user_id) do
    result =
      Repo.transaction(fn ->
        # If this preset is marked as default, clear others first
        if Map.get(attrs, "is_default") || Map.get(attrs, :is_default) do
          clear_default(user_id)
        end

        %ExportPreset{}
        |> ExportPreset.changeset(attrs)
        |> Ecto.Changeset.put_change(:user_id, user_id)
        |> Repo.insert()
        |> case do
          {:ok, p} -> p
          {:error, cs} -> Repo.rollback(cs)
        end
      end)

    case result do
      {:ok, preset} -> {:ok, preset}
      {:error, cs} -> {:error, cs}
    end
  end

  @doc "Updates an existing preset."
  def update_preset(%ExportPreset{} = preset, attrs) do
    Repo.transaction(fn ->
      if Map.get(attrs, "is_default") || Map.get(attrs, :is_default) do
        clear_default(preset.user_id)
      end

      preset
      |> ExportPreset.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, p} -> p
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
    |> case do
      {:ok, p} -> {:ok, p}
      {:error, cs} -> {:error, cs}
    end
  end

  @doc "Deletes a preset."
  def delete_preset(%ExportPreset{} = preset), do: Repo.delete(preset)

  @doc """
  Merges a preset's settings with any inline overrides from request params.
  Inline params take precedence.
  """
  def merge_settings(nil, inline), do: inline

  def merge_settings(%ExportPreset{settings: base}, inline) do
    Map.merge(stringify_keys(base), stringify_keys(inline))
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp clear_default(user_id) do
    from(p in ExportPreset,
      where: p.user_id == ^user_id and p.is_default == true
    )
    |> Repo.update_all(set: [is_default: false])
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
