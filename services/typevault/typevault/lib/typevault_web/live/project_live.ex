defmodule TypeVaultWeb.ProjectLive do
  use TypeVaultWeb, :live_view

  alias TypeVault.{Fonts, TvfParser}

  @max_file_size 5_000_000

  on_mount {TypeVaultWeb.Live.Auth, :require_authenticated_user}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Fonts.get_accessible_project(id, user.id) do
      {:ok, project} ->
        fonts       = Fonts.list_project_fonts(id)
        owner?      = project.user_id == user.id

        socket =
          socket
          |> assign(
               page_title:       project.name,
               project:          project,
               fonts:            fonts,
               owner?:           owner?,
               active_tab:       "fonts",
               preview_text:     "The quick brown fox",
               preview_size:     48,
               preview_svg:      nil,
               preview_loading:  false,
               selected_font_id: nil,
               show_upload:      false,
               upload_error:     nil,
               conn_or_lv_path:  "/studio/#{id}"
             )
          |> allow_upload(:tvf_file, accept: :any, max_entries: 1, max_file_size: 5_000_000, auto_upload: true)

        {:ok, socket}

      {:error, :not_found}  -> {:ok, assign(socket, not_found: true, page_title: "Not found", conn_or_lv_path: "/studio")}
      {:error, :forbidden}  -> {:ok, assign(socket, forbidden: true,  page_title: "Forbidden",  conn_or_lv_path: "/studio")}
    end
  end

  @impl true
  def handle_event("set-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  @impl true
  def handle_event("select-font", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected_font_id: id, preview_svg: nil)}
  end

  @impl true
  def handle_event("set-preview-text", %{"value" => v}, socket) do
    {:noreply, assign(socket, preview_text: v)}
  end

  @impl true
  def handle_event("set-preview-size", %{"value" => v}, socket) do
    size = String.to_integer(v) |> max(8) |> min(256)
    {:noreply, assign(socket, preview_size: size)}
  end

  @impl true
  def handle_event("render-preview", _, socket) do
    with font_id  when not is_nil(font_id) <- socket.assigns.selected_font_id,
         font     when not is_nil(font)    <- Fonts.get_font_file(font_id),
         {:ok, svg} <- TvfParser.render_text(font.data, socket.assigns.preview_text, socket.assigns.preview_size) do
      {:noreply,
       socket
       |> assign(preview_svg: svg, preview_loading: false)
       |> push_event("render-svg", %{svg: svg})}
    else
      nil         -> {:noreply, put_flash(socket, :error, "Select a font first.")}
      {:error, r} -> {:noreply, put_flash(socket, :error, "Render error: #{inspect(r)}")}
    end
  end

  @impl true
  def handle_event("toggle-publish", _, socket) do
    project    = socket.assigns.project
    new_public = !project.is_public

    case Fonts.publish_project(project, new_public) do
      {:ok, updated} ->
        msg = if new_public, do: "Project is now public.", else: "Project set to private."
        {:noreply, socket |> assign(project: updated) |> put_flash(:info, msg)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update visibility.")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-upload", _, socket) do
    {:noreply, assign(socket, show_upload: !socket.assigns.show_upload, upload_error: nil)}
  end

  @impl true
  def handle_event("save-font", _params, socket) do
    project = socket.assigns.project

    {done, in_progress} = uploaded_entries(socket, :tvf_file)
    require Logger
    Logger.info("save-font: done=#{length(done)} in_progress=#{length(in_progress)}")

    if in_progress != [] do
      {:noreply, assign(socket, upload_error: "File is still uploading, please wait…")}
    else

    results =
      consume_uploaded_entries(socket, :tvf_file, fn %{path: tmp_path}, entry ->
        data = File.read!(tmp_path)
        Logger.info("save-font: consuming entry=#{entry.client_name} size=#{byte_size(data)}")
        attrs = %{
          filename: sanitize_filename(entry.client_name),
          data: data,
          file_size: byte_size(data),
          format: "tvf"
        }

        case validate_and_create_font(attrs, project.id) do
          {:ok, ff, _parsed} -> {:ok, ff}
          {:error, reason} ->
            Logger.error("save-font: validation failed reason=#{inspect(reason)}")
            {:ok, {:error, reason}}
        end
      end)

    Logger.info("save-font: results=#{inspect(results)}")

    case results do
      [%TypeVault.Fonts.FontFile{}] ->
        fonts = Fonts.list_project_fonts(project.id)
        {:noreply,
         socket
         |> assign(fonts: fonts, show_upload: false, upload_error: nil)
         |> put_flash(:info, "Font uploaded successfully.")}

      [{:error, reason}] ->
        {:noreply, assign(socket, upload_error: "Upload failed: #{inspect(reason)}")}

      [] ->
        {:noreply, assign(socket, upload_error: "Upload failed: no file was transferred yet, please try again.")}

      _ ->
        {:noreply, assign(socket, upload_error: "Upload failed. Make sure it's a valid .tvf file.")}
    end
    end
  end

  defp tab_style(tab, active) do
    base = "padding:.45rem 1rem;border-radius:7px;font-size:.85rem;cursor:pointer;border:none;font-weight:500;transition:all .15s;"
    if tab == active,
      do:   base <> "background:rgba(124,58,237,.2);color:#a78bfa;",
      else: base <> "background:transparent;color:#64748b;"
  end

  defp fmt_bytes(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)} MB"
  defp fmt_bytes(n) when n >= 1_000,     do: "#{Float.round(n / 1_000, 1)} KB"
  defp fmt_bytes(n),                     do: "#{n} B"

  defp validate_and_create_font(attrs, project_id) do
    data = attrs.data

    with true <- byte_size(data) <= @max_file_size || {:error, :file_too_large},
         {:ok, parsed} <- TvfParser.parse_font(data),
         {:ok, ff} <- Fonts.create_font_file(Map.put(attrs, :parsed_metadata, parsed.metadata), project_id) do
      {:ok, ff, parsed}
    end
  end

  defp sanitize_filename(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.slice(0, 255)
  end

  @impl true
  def render(%{not_found: true} = assigns) do
    ~H"""
    <div style="text-align:center;padding:8rem 2rem;color:#64748b;">
      <p style="font-size:1.5rem;margin-bottom:.5rem;">404</p>
      <p>Project not found.</p>
      <a href="/studio" style="color:#a78bfa;font-size:.875rem;text-decoration:none;">← Back to studio</a>
    </div>
    """
  end

  @impl true
  def render(%{forbidden: true} = assigns) do
    ~H"""
    <div style="text-align:center;padding:8rem 2rem;color:#64748b;">
      <p style="font-size:1.5rem;margin-bottom:.5rem;">Access denied</p>
      <p>You don't have permission to view this project.</p>
      <a href="/studio" style="color:#a78bfa;font-size:.875rem;text-decoration:none;">← Back to studio</a>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="min-height:100vh;">

      <%# ── Project header ────────────────────────────────────────────────── %>
      <div style="border-bottom:1px solid rgba(255,255,255,.06);padding:2rem 1.5rem 1.25rem;">
        <div style="max-width:1280px;margin:0 auto;">

          <div style="display:flex;align-items:flex-start;justify-content:space-between;flex-wrap:wrap;gap:1rem;margin-bottom:1.25rem;">
            <div>
              <div style="display:flex;align-items:center;gap:.5rem;margin-bottom:.2rem;">
                <a href="/studio" style="color:#475569;font-size:.82rem;text-decoration:none;">Studio</a>
                <span style="color:#334155;">/</span>
                <span style="color:#94a3b8;font-size:.82rem;"><%= @project.name %></span>
              </div>
              <h1 style="font-size:1.6rem;font-weight:800;letter-spacing:-.025em;"><%= @project.name %></h1>
              <p style="color:#64748b;font-size:.875rem;margin-top:.25rem;"><%= @project.description || "" %></p>
            </div>

            <%= if @owner? do %>
              <div style="display:flex;align-items:center;gap:.75rem;flex-wrap:wrap;">
                <div
                  phx-click="toggle-publish"
                  style={"display:flex;align-items:center;gap:.5rem;padding:.45rem .9rem;border-radius:8px;cursor:pointer;border:1px solid rgba(255,255,255,.09);font-size:.82rem;" <> if @project.is_public, do: "color:#4ade80;background:rgba(74,222,128,.06);", else: "color:#94a3b8;background:rgba(255,255,255,.03);"}
                >
                  <span style="font-size:.7rem;"><%= if @project.is_public, do: "●", else: "○" %></span>
                  <%= if @project.is_public, do: "Public", else: "Private" %>
                </div>

                <a
                  href={"/studio/#{@project.id}/export"}
                  style="display:flex;align-items:center;gap:.4rem;padding:.45rem .9rem;background:#7c3aed;border:none;border-radius:8px;color:#fff;font-size:.82rem;font-weight:600;text-decoration:none;"
                >
                  ↗ Export
                </a>
              </div>
            <% end %>
          </div>

          <%# Tabs %>
          <div style="display:flex;gap:.25rem;">
            <%= for {tab, label} <- (if @owner?, do: [{"fonts", "Fonts"}, {"preview", "Preview"}, {"activity", "Activity"}, {"settings", "Settings"}], else: [{"fonts", "Fonts"}, {"preview", "Preview"}, {"activity", "Activity"}]) do %>
              <button phx-click="set-tab" phx-value-tab={tab} style={tab_style(tab, @active_tab)}>
                <%= label %>
                <%= if tab == "fonts" do %>
                  <span style="margin-left:.4rem;background:rgba(255,255,255,.07);padding:.1rem .4rem;border-radius:100px;font-size:.68rem;color:#64748b;">
                    <%= length(@fonts) %>
                  </span>
                <% end %>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%# ── Tab content ────────────────────────────────────────────────────── %>
      <div style="max-width:1280px;margin:0 auto;padding:2rem 1.5rem;">

        <%= if @active_tab == "fonts" do %>
          <%# ── Fonts tab ── %>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:2.5rem;">
            <div>
              <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:1.1rem;">
                <h2 style="font-size:1.05rem;font-weight:600;">Font files</h2>
                <%= if @owner? do %>
                  <button phx-click="toggle-upload"
                    style="padding:.4rem .9rem;background:#7c3aed;border:none;border-radius:7px;color:#fff;font-size:.78rem;font-weight:600;cursor:pointer;">
                    + Upload .tvf
                  </button>
                <% end %>
              </div>

              <%= if @show_upload do %>
                <form phx-submit="save-font" phx-change="validate" style="background:#13131f;border:1px solid rgba(124,58,237,.3);border-radius:10px;padding:1rem;margin-bottom:1rem;">
                  <%= if @upload_error do %>
                    <p style="color:#fca5a5;font-size:.78rem;margin-bottom:.5rem;"><%= @upload_error %></p>
                  <% end %>
                  <.live_file_input upload={@uploads.tvf_file}
                    style="display:block;width:100%;font-size:.8rem;color:#94a3b8;margin-bottom:.75rem;"/>
                  <div style="display:flex;gap:.5rem;justify-content:flex-end;">
                    <button type="button" phx-click="toggle-upload"
                      style="padding:.4rem .85rem;background:transparent;border:1px solid rgba(255,255,255,.1);border-radius:7px;color:#94a3b8;font-size:.78rem;cursor:pointer;">Cancel</button>
                    <button type="submit" disabled={Enum.empty?(@uploads.tvf_file.entries) or Enum.any?(@uploads.tvf_file.entries, &(not &1.done?))}
                      style={"padding:.4rem .85rem;border:none;border-radius:7px;font-size:.78rem;font-weight:600;cursor:pointer;" <> if Enum.empty?(@uploads.tvf_file.entries) or Enum.any?(@uploads.tvf_file.entries, &(not &1.done?)), do: "background:#334155;color:#64748b;cursor:not-allowed;", else: "background:#7c3aed;color:#fff;"}>
                      Upload
                    </button>
                  </div>
                </form>
              <% end %>

              <%= if length(@fonts) == 0 do %>
                <div style="border:1px dashed rgba(255,255,255,.08);border-radius:12px;padding:3rem 1.5rem;text-align:center;">
                  <p style="color:#64748b;font-size:.875rem;margin-bottom:.5rem;">No fonts yet</p>
                  <p style="color:#475569;font-size:.78rem;">Click <strong style="color:#94a3b8;">+ Upload .tvf</strong> to add your first font.</p>
                </div>
              <% else %>
                <div style="display:flex;flex-direction:column;gap:.6rem;">
                  <%= for font <- @fonts do %>
                    <div
                      phx-click="select-font"
                      phx-value-id={font.id}
                      style={"display:flex;align-items:center;justify-content:space-between;padding:.85rem 1rem;border-radius:10px;cursor:pointer;border:1px solid;transition:all .15s;" <> if font.id == @selected_font_id, do: "border-color:rgba(124,58,237,.4);background:rgba(124,58,237,.08);", else: "border-color:rgba(255,255,255,.07);background:#13131f;"}
                    >
                      <div style="display:flex;align-items:center;gap:.75rem;">
                        <div style="width:36px;height:36px;border-radius:8px;background:#1a1a2e;display:flex;align-items:center;justify-content:center;font-size:.8rem;font-weight:700;color:#7c3aed;flex-shrink:0;">TVF</div>
                        <div>
                          <p style="font-size:.875rem;font-weight:500;"><%= font.filename %></p>
                          <p style="font-size:.72rem;color:#475569;margin-top:.1rem;"><%= fmt_bytes(font.file_size) %></p>
                        </div>
                      </div>
                      <div style="display:flex;align-items:center;gap:.6rem;">
                        <%= if font.id == @selected_font_id do %>
                          <span style="font-size:.72rem;color:#a78bfa;font-weight:600;">Selected</span>
                        <% end %>
                        <a
                          href={"/fonts/#{font.id}/download"}
                          phx-click={JS.dispatch("click")}
                          onclick="event.stopPropagation()"
                          style="padding:.25rem .65rem;background:rgba(124,58,237,.15);border:1px solid rgba(124,58,237,.3);border-radius:6px;color:#a78bfa;font-size:.7rem;font-weight:600;text-decoration:none;white-space:nowrap;"
                          title="Download font file"
                        >↓ Download</a>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%# Quick preview panel %>
            <div>
              <h2 style="font-size:1.05rem;font-weight:600;margin-bottom:1.1rem;">Quick preview</h2>
              <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;display:flex;flex-direction:column;gap:1rem;">

                <div>
                  <label style="display:block;font-size:.75rem;color:#64748b;margin-bottom:.35rem;">Preview text</label>
                  <input
                    type="text"
                    value={@preview_text}
                    phx-keyup="set-preview-text"
                    style="width:100%;padding:.6rem .9rem;background:#09090f;border:1px solid rgba(255,255,255,.09);border-radius:8px;color:#e2e8f0;font-size:.875rem;outline:none;"
                    onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.09)'"
                  />
                </div>

                <div>
                  <label style="display:block;font-size:.75rem;color:#64748b;margin-bottom:.35rem;">Size: <%= @preview_size %>px</label>
                  <input type="range" name="value" min="12" max="128" step="4" value={@preview_size} phx-change="set-preview-size"
                    style="width:100%;accent-color:#7c3aed;"/>
                </div>

                <button
                  phx-click="render-preview"
                  disabled={is_nil(@selected_font_id)}
                  style={"width:100%;padding:.65rem;border:none;border-radius:8px;font-size:.875rem;font-weight:600;" <> if @selected_font_id, do: "background:#7c3aed;color:#fff;cursor:pointer;", else: "background:#1e1e35;color:#475569;cursor:not-allowed;"}
                >
                  <%= if @preview_loading, do: "Rendering…", else: "Render preview" %>
                </button>

                <div id="svg-preview" phx-hook="SvgFrame"
                  style={"min-height:80px;border-radius:8px;display:flex;align-items:center;justify-content:center;" <> if @preview_svg, do: "background:#09090f;border:1px solid rgba(255,255,255,.07);padding:.75rem;", else: "background:rgba(255,255,255,.02);"}>
                  <%= if is_nil(@preview_svg) do %>
                    <p style="color:#334155;font-size:.8rem;">Select a font and click Render</p>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

        <% end %>

        <%= if @active_tab == "preview" do %>
          <%# ── Preview tab (draft preview) ── %>
          <div style="max-width:640px;">
            <h2 style="font-size:1.05rem;font-weight:600;margin-bottom:.4rem;">Draft Preview</h2>
            <p style="color:#64748b;font-size:.82rem;margin-bottom:1.5rem;">
              Paste a raw TVF opcode stream (base64) to preview before saving.
              The stream is validated and rendered live.
            </p>
            <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;display:flex;flex-direction:column;gap:1rem;">
              <div>
                <label style="display:block;font-size:.75rem;color:#64748b;margin-bottom:.35rem;">Base64 opcode stream</label>
                <textarea rows="5" placeholder="BAD+CAFE…" id="draft-input"
                  style="width:100%;padding:.7rem .9rem;background:#09090f;border:1px solid rgba(255,255,255,.09);border-radius:8px;color:#e2e8f0;font-size:.82rem;font-family:monospace;outline:none;resize:vertical;"
                  onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.09)'"></textarea>
              </div>
              <button onclick={"submitDraft('#{@project.id}')"} id="draft-btn"
                style="padding:.65rem 1.25rem;background:#7c3aed;border:none;border-radius:8px;color:#fff;font-size:.875rem;font-weight:600;cursor:pointer;align-self:flex-start;">
                Validate & Preview
              </button>
              <div id="draft-result" style="min-height:60px;"></div>
            </div>
          </div>
          <script>
            function submitDraft(projectId) {
              const token = document.cookie.match(/auth_token=([^;]+)/)?.[1] || localStorage.getItem('tv_token')
              const font  = document.getElementById('draft-input').value.trim()
              const btn   = document.getElementById('draft-btn')
              const out   = document.getElementById('draft-result')
              if (!font) return
              btn.textContent = 'Rendering…'
              fetch(`/api/projects/${projectId}/preview_draft`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
                body: JSON.stringify({ font })
              })
              .then(r => r.json())
              .then(d => {
                btn.textContent = 'Validate & Preview'
                out.innerHTML = d.svg ? d.svg : `<p style="color:#f87171;font-size:.82rem;">${d.error || 'Error'}</p>`
              })
              .catch(() => { btn.textContent = 'Validate & Preview'; out.textContent = 'Request failed.' })
            }
          </script>

        <% end %>

        <%= if @active_tab == "activity" do %>
          <div>
            <h2 style="font-size:1.05rem;font-weight:600;margin-bottom:1rem;">Activity log</h2>
            <div style="border:1px solid rgba(255,255,255,.07);border-radius:12px;overflow:hidden;">
              <div style="padding:1.5rem;text-align:center;color:#475569;font-size:.875rem;">
                Event log available via <a href={"/api/projects/#{@project.id}/activity"} style="color:#7c3aed;text-decoration:none;">GET /api/projects/:id/activity</a>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @active_tab == "settings" do %>
          <div style="max-width:500px;">
            <h2 style="font-size:1.05rem;font-weight:600;margin-bottom:1.2rem;">Project settings</h2>
            <div style="display:flex;flex-direction:column;gap:1rem;">
              <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
                <p style="font-size:.875rem;font-weight:500;margin-bottom:.25rem;">Project ID</p>
                <p style="font-family:monospace;font-size:.78rem;color:#7c3aed;"><%= @project.id %></p>
              </div>
              <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
                <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:.5rem;">
                  <p style="font-size:.875rem;font-weight:500;">Design notes</p>
                  <span style="font-size:.68rem;background:rgba(239,68,68,.12);color:#f87171;border:1px solid rgba(239,68,68,.25);border-radius:100px;padding:.1rem .55rem;font-weight:600;">PRIVATE</span>
                </div>
                <%= if @project.design_notes && @project.design_notes != "" do %>
                  <pre style="font-family:monospace;font-size:.8rem;color:#e2e8f0;background:#09090f;border:1px solid rgba(255,255,255,.07);border-radius:8px;padding:.75rem 1rem;white-space:pre-wrap;word-break:break-all;margin:0;"><%= @project.design_notes %></pre>
                <% else %>
                  <p style="font-size:.78rem;color:#475569;font-style:italic;">No notes set. Update via <code style="color:#7c3aed;background:rgba(124,58,237,.1);padding:.1rem .35rem;border-radius:4px;">PUT /api/projects/:id</code> with <code style="color:#7c3aed;background:rgba(124,58,237,.1);padding:.1rem .35rem;border-radius:4px;">design_notes</code> field.</p>
                <% end %>
              </div>
              <div style="background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:12px;padding:1.25rem;">
                <p style="font-size:.875rem;font-weight:500;margin-bottom:.25rem;">Collaborators</p>
                <p style="font-size:.78rem;color:#64748b;">Manage access via <a href={"/api/projects/#{@project.id}/members"} style="color:#7c3aed;text-decoration:none;">members API</a>.</p>
              </div>
            </div>
          </div>
        <% end %>

      </div>
    </div>
    """
  end
end
