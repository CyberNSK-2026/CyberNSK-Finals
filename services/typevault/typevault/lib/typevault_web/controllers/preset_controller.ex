defmodule TypeVaultWeb.PresetController do
  use TypeVaultWeb, :controller

  alias TypeVault.{Presets, Guardian}

  action_fallback TypeVaultWeb.FallbackController

  @doc "GET /api/export/presets — list all presets for the current user"
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    presets = Presets.list_presets(user.id)
    json(conn, %{presets: Enum.map(presets, &preset_json/1)})
  end

  @doc "POST /api/export/presets — create a new named preset"
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    attrs = Map.take(params, ~w(name description settings is_default))

    case Presets.create_preset(attrs, user.id) do
      {:ok, preset} ->
        conn
        |> put_status(:created)
        |> json(%{preset: preset_json(preset)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "GET /api/export/presets/:id — fetch a single preset"
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Presets.get_preset(id, user.id) do
      {:ok, preset} -> json(conn, %{preset: preset_json(preset)})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "preset not found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "access denied"})
    end
  end

  @doc "PUT /api/export/presets/:id — update a preset"
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    attrs = Map.take(params, ~w(name description settings is_default))

    with {:ok, preset} <- Presets.get_preset(id, user.id),
         {:ok, updated} <- Presets.update_preset(preset, attrs) do
      json(conn, %{preset: preset_json(updated)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "preset not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "access denied"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "DELETE /api/export/presets/:id — delete a preset"
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, preset} <- Presets.get_preset(id, user.id),
         {:ok, _} <- Presets.delete_preset(preset) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "preset not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "access denied"})
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp preset_json(preset) do
    %{
      id: preset.id,
      name: preset.name,
      description: preset.description,
      settings: preset.settings,
      is_default: preset.is_default,
      inserted_at: preset.inserted_at,
      updated_at: preset.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
