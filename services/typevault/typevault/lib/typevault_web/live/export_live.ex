defmodule TypeVaultWeb.ExportLive do
  use TypeVaultWeb, :live_view

  alias TypeVault.{Fonts, Presets}

  on_mount {TypeVaultWeb.Live.Auth, :require_authenticated_user}

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    user = socket.assigns.current_user

    case Fonts.get_accessible_project(project_id, user.id) do
      {:ok, project} ->
        presets = case Presets.list_presets(user.id) do
          {:ok, p}  -> p
          presets when is_list(presets) -> presets
          _         -> []
        end

        {:ok,
         assign(socket,
           page_title:         "Export · #{project.name}",
           project:            project,
           presets:            presets,
           format:             "svg",
           sample_text:        "The quick brown fox jumps over the lazy dog",
           pipeline_strip:     false,
           pipeline_normalise: false,
           pipeline_watermark: false,
           preset_name:        "",
           exporting:          false,
           result_svg:         nil,
           result_error:       nil,
           show_save_preset:   false,
           ctx_seed:           0,
           ctx_mode:           0,
           ctx_bias:           0,
           conn_or_lv_path:    "/studio/#{project_id}/export"
         )}

      _ ->
        {:ok, assign(socket, not_found: true, page_title: "Not found", conn_or_lv_path: "/studio")}
    end
  end

  @impl true
  def handle_event("set-format", %{"format" => f}, socket) when f in ~w(svg specimen) do
    {:noreply, assign(socket, format: f)}
  end

  @impl true
  def handle_event("set-sample-text", %{"value" => v}, socket) do
    {:noreply, assign(socket, sample_text: v)}
  end

  @impl true
  def handle_event("toggle-" <> stage, _, socket) when stage in ~w(strip normalise watermark) do
    key = :"pipeline_#{stage}"
    {:noreply, assign(socket, key, !Map.get(socket.assigns, key))}
  end

  @impl true
  def handle_event("set-preset-name", %{"value" => v}, socket) do
    {:noreply, assign(socket, preset_name: v)}
  end

  @impl true
  def handle_event("toggle-save-preset", _, socket) do
    {:noreply, assign(socket, show_save_preset: !socket.assigns.show_save_preset)}
  end

  @impl true
  def handle_event("load-preset", %{"id" => preset_id}, socket) do
    user = socket.assigns.current_user
    case Presets.get_preset(preset_id, user.id) do
      {:ok, preset} ->
        s = preset.settings || %{}
        {:noreply,
         assign(socket,
           format:             s["format"] || socket.assigns.format,
           sample_text:        s["sample_text"] || socket.assigns.sample_text,
           pipeline_strip:     s["strip"] || false,
           pipeline_normalise: s["normalise"] || false,
           pipeline_watermark: s["watermark"] || false
         )}
      _ -> {:noreply, socket}
    end
  end

  # Trigger the real export — calls the JSON API endpoint from the browser
  # so that the __evs cookie is included automatically.
  # The JS hook handles the fetch, the LiveView receives the result via pushEvent.
  @impl true
  def handle_event("export", _, socket) do
    {:noreply,
     socket
     |> assign(exporting: true, result_svg: nil, result_error: nil)
     |> push_event("do-export", %{
         project_id:   socket.assigns.project.id,
         format:       socket.assigns.format,
         sample_text:  socket.assigns.sample_text
       })}
  end

  @impl true
  def handle_event("export-result", %{"svg" => svg}, socket) do
    format   = socket.assigns.format
    filename = "#{socket.assigns.project.name}_export.#{if format == "specimen", do: "svg", else: format}"
    {:noreply,
     socket
     |> assign(exporting: false, result_svg: svg, result_error: nil)
     |> push_event("render-svg", %{svg: svg})
     |> push_event("download", %{content: svg, filename: filename, type: "image/svg+xml"})}
  end

  @impl true
  def handle_event("export-result", %{"error" => err}, socket) do
    {:noreply, assign(socket, exporting: false, result_svg: nil, result_error: err)}
  end

  # Persist UI preferences into the __evs cookie for client-only rendering hints.
  @impl true
  def handle_event("save-settings", _, socket) do
    pipeline =
      []
      |> add_stage(socket.assigns.pipeline_strip, "strip")
      |> add_stage(socket.assigns.pipeline_normalise, "normalise")
      |> add_stage(socket.assigns.pipeline_watermark, "watermark")

    settings = %{
      format:          socket.assigns.format,
      sample_text:     socket.assigns.sample_text,
      render_pipeline: pipeline
    }

    {:noreply,
     socket
     |> put_flash(:info, "Settings saved to session.")
     |> push_event("save-evs-settings", %{settings: settings})}
  end

  defp add_stage(list, true, name),  do: list ++ [%{stage: name}]
  defp add_stage(list, false, _),    do: list

  defp stage_enabled?(assigns, stage) do
    Map.get(assigns, :"pipeline_#{stage}", false)
  end

  @impl true
  def render(%{not_found: true} = assigns) do
    ~H"""
    <div style="text-align:center;padding:8rem 2rem;color:#64748b;">
      <p>Project not found.</p>
      <a href="/studio" style="color:#a78bfa;font-size:.875rem;text-decoration:none;">← Studio</a>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="min-height:100vh;">

      <%# ── Header ──────────────────────────────────────────────────────────── %>
      <div style="border-bottom:1px solid rgba(255,255,255,.06);padding:2rem 1.5rem 1.25rem;">
        <div style="max-width:1280px;margin:0 auto;">
          <div style="display:flex;align-items:center;gap:.5rem;margin-bottom:.4rem;">
            <a href="/studio" style="color:#475569;font-size:.82rem;text-decoration:none;">Studio</a>
            <span style="color:#334155;">/</span>
            <a href={"/studio/#{@project.id}"} style="color:#475569;font-size:.82rem;text-decoration:none;"><%= @project.name %></a>
            <span style="color:#334155;">/</span>
            <span style="color:#94a3b8;font-size:.82rem;">Export</span>
          </div>
          <h1 style="font-size:1.6rem;font-weight:800;letter-spacing:-.025em;">Export Center</h1>
          <p style="color:#64748b;font-size:.875rem;margin-top:.25rem;">Configure your export pipeline and render to file.</p>
        </div>
      </div>

      <div style="max-width:1280px;margin:2rem auto;padding:0 1.5rem;display:grid;grid-template-columns:340px 1fr;gap:2.5rem;align-items:start;">

        <%# ── Left: settings panel ────────────────────────────────────────── %>
        <div style="display:flex;flex-direction:column;gap:1.25rem;">

          <%# Format selector %>
          <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
            <p style="font-size:.82rem;font-weight:600;color:#94a3b8;text-transform:uppercase;letter-spacing:.06em;margin-bottom:.9rem;">Output format</p>
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:.6rem;">
              <%= for {fmt, desc} <- [{"svg", "SVG Vector"}, {"specimen", "Specimen Sheet"}] do %>
                <div
                  phx-click="set-format"
                  phx-value-format={fmt}
                  style={"padding:.75rem;border-radius:9px;cursor:pointer;border:1px solid;transition:all .15s;" <> if fmt == @format, do: "border-color:rgba(124,58,237,.45);background:rgba(124,58,237,.1);", else: "border-color:rgba(255,255,255,.07);background:rgba(255,255,255,.02);"}
                >
                  <p style={"font-size:.85rem;font-weight:600;" <> if fmt == @format, do: "color:#a78bfa;", else: "color:#94a3b8;"}><%= String.upcase(fmt) %></p>
                  <p style="font-size:.72rem;color:#475569;margin-top:.2rem;"><%= desc %></p>
                </div>
              <% end %>
            </div>
          </div>

          <%# Sample text %>
          <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
            <p style="font-size:.82rem;font-weight:600;color:#94a3b8;text-transform:uppercase;letter-spacing:.06em;margin-bottom:.9rem;">Sample text</p>
            <textarea
              rows="3"
              phx-keyup="set-sample-text"
              style="width:100%;padding:.65rem .9rem;background:#09090f;border:1px solid rgba(255,255,255,.09);border-radius:8px;color:#e2e8f0;font-size:.82rem;outline:none;resize:none;"
              onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.09)'"
            ><%= @sample_text %></textarea>
          </div>

          <%# Pipeline stages %>
          <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
            <p style="font-size:.82rem;font-weight:600;color:#94a3b8;text-transform:uppercase;letter-spacing:.06em;margin-bottom:.9rem;">
              Post-process pipeline
            </p>
            <div style="display:flex;flex-direction:column;gap:.7rem;">
              <%= for {stage, label, desc} <- [
                {"strip",     "Strip metadata",     "Remove embedded font metadata from SVG output"},
                {"normalise", "Normalise colours",  "Convert all colour references to sRGB hex"},
                {"watermark", "Studio watermark",   "Inject studio branding glyph into the render"}
              ] do %>
                <div
                  phx-click={"toggle-#{stage}"}
                  style="display:flex;align-items:center;justify-content:space-between;cursor:pointer;user-select:none;"
                >
                  <div>
                    <p style="font-size:.875rem;font-weight:500;"><%= label %></p>
                    <p style="font-size:.72rem;color:#64748b;margin-top:.1rem;"><%= desc %></p>
                  </div>
                  <div style={"width:38px;height:22px;border-radius:100px;cursor:pointer;transition:background .2s;position:relative;flex-shrink:0;" <> if stage_enabled?(assigns, stage), do: "background:#7c3aed;", else: "background:#334155;"}>
                    <div style={"width:16px;height:16px;border-radius:50%;background:#fff;position:absolute;top:3px;transition:left .2s;" <> if stage_enabled?(assigns, stage), do: "left:19px;", else: "left:3px;"}></div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%# Gallery context — populated client-side from /api/export/context %>
          <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
            <p style="font-size:.82rem;font-weight:600;color:#94a3b8;text-transform:uppercase;letter-spacing:.06em;margin-bottom:.9rem;">
              Gallery context
            </p>
            <div
              id="ctx-panel"
              phx-hook="ContextPanel"
              phx-update="ignore"
              data-seed={@ctx_seed}
              data-mode={@ctx_mode}
              data-bias={@ctx_bias}
              style="display:flex;flex-direction:column;gap:.4rem;max-height:260px;overflow-y:auto;"
            >
              <p style="color:#475569;font-size:.78rem;">Loading related projects…</p>
            </div>
          </div>

          <%# Presets %>
          <%= if length(@presets) > 0 do %>
            <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
              <p style="font-size:.82rem;font-weight:600;color:#94a3b8;text-transform:uppercase;letter-spacing:.06em;margin-bottom:.9rem;">Named presets</p>
              <div style="display:flex;flex-direction:column;gap:.45rem;">
                <%= for preset <- @presets do %>
                  <button
                    phx-click="load-preset"
                    phx-value-id={preset.id}
                    style="display:flex;align-items:center;justify-content:space-between;padding:.55rem .8rem;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.07);border-radius:7px;cursor:pointer;text-align:left;"
                    onmouseover="this.style.borderColor='rgba(124,58,237,.3)'" onmouseout="this.style.borderColor='rgba(255,255,255,.07)'"
                  >
                    <span style="font-size:.82rem;color:#e2e8f0;"><%= preset.name %></span>
                    <span style="font-size:.7rem;color:#475569;">Load ↗</span>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%# Actions %>
          <div style="display:flex;flex-direction:column;gap:.65rem;">
            <button
              phx-click="save-settings"
              style="padding:.7rem 1rem;background:transparent;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#94a3b8;font-size:.875rem;font-weight:500;cursor:pointer;transition:all .15s;"
              onmouseover="this.style.borderColor='rgba(255,255,255,.2)';this.style.color='#e2e8f0'"
              onmouseout="this.style.borderColor='rgba(255,255,255,.1)';this.style.color='#94a3b8'"
            >
              Save to session
            </button>

            <button
              phx-click="export"
              phx-hook="ExportBridge"
              style={"padding:.8rem 1rem;border:none;border-radius:9px;color:#fff;font-size:.9rem;font-weight:600;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:.5rem;transition:all .2s;" <> if @exporting, do: "background:#334155;cursor:wait;", else: "background:linear-gradient(135deg,#7c3aed,#5b21b6);"}
              id="export-btn"
            >
              <%= if @exporting do %>
                <span style="display:inline-block;width:14px;height:14px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .7s linear infinite;"></span>
                Exporting…
              <% else %>
                ↗ Export now
              <% end %>
            </button>
          </div>

        </div>

        <%# ── Right: preview / result ─────────────────────────────────────── %>
        <div>
          <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;overflow:hidden;">
            <div style="padding:1rem 1.25rem;border-bottom:1px solid rgba(255,255,255,.06);display:flex;align-items:center;justify-content:space-between;">
              <p style="font-size:.82rem;font-weight:600;color:#94a3b8;text-transform:uppercase;letter-spacing:.06em;">Output preview</p>
              <%= if @result_svg do %>
                <button
                  id="copy-svg"
                  phx-hook="CopyButton"
                  data-copy={@result_svg}
                  style="font-size:.75rem;color:#a78bfa;background:none;border:none;cursor:pointer;padding:.25rem .5rem;"
                >Copy SVG</button>
              <% end %>
            </div>

            <div id="export-downloader" phx-hook="DownloadFile" style="display:none;"></div>
            <div id="export-result" phx-hook="SvgFrame" style="padding:1.5rem;min-height:300px;display:flex;align-items:center;justify-content:center;">
              <%= cond do %>
                <% @result_error != nil -> %>
                  <div style="text-align:center;">
                    <p style="color:#f87171;font-size:.875rem;margin-bottom:.5rem;">Export failed</p>
                    <p style="color:#475569;font-size:.78rem;font-family:monospace;"><%= @result_error %></p>
                  </div>
                <% @result_svg != nil -> %>
                  <%# SVG injected by SvgFrame hook %>
                  <span></span>
                <% true -> %>
                  <div style="text-align:center;color:#334155;">
                    <div style="font-size:3rem;margin-bottom:.75rem;opacity:.3;">◈</div>
                    <p style="font-size:.82rem;">Configure settings and click <strong>Export now</strong></p>
                  </div>
              <% end %>
            </div>
          </div>

          <%# Pipeline summary %>
          <div style="margin-top:1.25rem;background:#0e0e1a;border:1px solid rgba(255,255,255,.05);border-radius:10px;padding:1rem 1.25rem;">
            <p style="font-size:.72rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#334155;margin-bottom:.6rem;">Active pipeline</p>
            <div style="display:flex;flex-wrap:wrap;gap:.4rem;">
              <%= for {stage, label} <- [{"strip", "strip"}, {"normalise", "normalise"}, {"watermark", "watermark"}] do %>
                <span style={"padding:.15rem .6rem;border-radius:100px;font-size:.7rem;font-weight:600;font-family:monospace;" <> if stage_enabled?(assigns, stage), do: "background:rgba(124,58,237,.15);color:#a78bfa;border:1px solid rgba(124,58,237,.3);", else: "background:rgba(255,255,255,.03);color:#334155;border:1px solid rgba(255,255,255,.05);"}>
                  <%= label %>
                </span>
              <% end %>
              <span style="padding:.15rem .6rem;border-radius:100px;font-size:.7rem;font-weight:600;font-family:monospace;background:rgba(255,255,255,.03);color:#475569;border:1px solid rgba(255,255,255,.05);">
                format=<%= @format %>
              </span>
            </div>
          </div>
        </div>

      </div>
    </div>

    """
  end
end
