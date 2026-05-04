defmodule TypeVaultWeb.ExportController do
  use TypeVaultWeb, :controller

  alias TypeVault.{Fonts, Presets, TvfParser, Events, Guardian}
  alias TypeVault.Export.{SessionCodec, PipelineRunner, Context}

  action_fallback TypeVaultWeb.FallbackController

  @supported_formats ~w(svg png_base64 specimen)

  def create(conn, %{"project_id" => project_id} = params) do
    user = Guardian.Plug.current_resource(conn)

    session_settings = SessionCodec.decode(conn.cookies["__evs"])
    preset           = resolve_preset(params, user.id)
    effective        = merge_settings(session_settings, preset, params)

    sample_text = Map.get(effective, "sample_text", "The quick brown fox")
    format      = effective |> Map.get("format", "svg") |> validate_format()

    with {:ok, project}   <- Fonts.get_accessible_project(project_id, user.id),
         {:ok, font_file} <- Fonts.get_project_font(project_id),
         {:ok, rendered}  <- do_render(font_file.data, sample_text, format) do

      final_output = PipelineRunner.run(rendered, session_settings)

      Events.log(project_id, user.id, "exported", %{
        format:    format,
        preset_id: params["preset_id"]
      })

      conn
      |> put_resp_content_type(content_type_for(format))
      |> put_resp_header("x-font-name", project.name)
      |> send_resp(200, final_output)
    end
  end

  def get_settings(conn, _params) do
    settings = SessionCodec.decode(conn.cookies["__evs"])
    safe     = Map.take(settings, [:format, :quality, :width, :height, :background])
    json(conn, %{settings: safe})
  end

  def context(conn, params) do
    user     = Guardian.Plug.current_resource(conn)
    projects = Fonts.list_context_projects(user.id)

    opts = %{
      seed: Map.get(params, "seed"),
      mode: Map.get(params, "mode"),
      bias: Map.get(params, "bias")
    }

    json(conn, %{items: Context.build(projects, opts)})
  end

  def save_settings(conn, params) do
    allowed = ~w(format quality width height background)a

    settings =
      params
      |> Map.take(Enum.map(allowed, &to_string/1))
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    conn
    |> put_resp_cookie("__evs", SessionCodec.encode(settings),
      http_only: true,
      max_age: 60 * 60 * 24 * 30,
      same_site: "Lax"
    )
    |> json(%{message: "settings saved"})
  end

  defp do_render(font_data, text, "svg"),
    do: TvfParser.render_text(font_data, text, 48)

  defp do_render(font_data, text, "specimen"),
    do: TvfParser.render_specimen(font_data, text)

  defp do_render(font_data, text, _format),
    do: TvfParser.render_text(font_data, text, 48)

  defp resolve_preset(%{"preset_id" => preset_id}, user_id) when is_binary(preset_id) do
    case Presets.get_preset(preset_id, user_id) do
      {:ok, preset} -> preset
      _             -> nil
    end
  end

  defp resolve_preset(_params, _user_id), do: nil

  defp merge_settings(session, preset, inline) do
    base        = session |> stringify_keys()
    from_preset = Presets.merge_settings(preset, %{})
    from_inline = Map.take(inline, ~w(sample_text format quality width height background))

    base |> Map.merge(from_preset) |> Map.merge(from_inline)
  end

  defp validate_format(f) when f in @supported_formats, do: f
  defp validate_format(_), do: "svg"

  defp content_type_for("svg"),        do: "image/svg+xml"
  defp content_type_for("png_base64"), do: "application/json"
  defp content_type_for(_),            do: "image/svg+xml"

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
