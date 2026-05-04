defmodule TypeVaultWeb.StudioLive do
  use TypeVaultWeb, :live_view

  alias TypeVault.Fonts

  on_mount {TypeVaultWeb.Live.Auth, :require_authenticated_user}

  @impl true
  def mount(_params, _session, socket) do
    user     = socket.assigns.current_user
    projects = Fonts.list_user_projects(user.id)

    total_fonts     = Enum.sum(Enum.map(projects, fn p -> length(p.font_files || []) end))
    total_downloads = Enum.sum(Enum.map(projects, fn p -> p.downloads || 0 end))

    {:ok,
     assign(socket,
       page_title:       "Studio",
       projects:         projects,
       total_fonts:      total_fonts,
       total_downloads:  total_downloads,
       show_new_modal:   false,
       new_name:         "",
       new_desc:         "",
       new_public:       false,
       creating:         false,
       form_error:       nil,
       conn_or_lv_path:  "/studio"
     )}
  end

  @impl true
  def handle_event("open-new-modal", _, socket) do
    {:noreply, assign(socket, show_new_modal: true, form_error: nil)}
  end

  @impl true
  def handle_event("close-modal", _, socket) do
    {:noreply, assign(socket, show_new_modal: false)}
  end

  @impl true
  def handle_event("set-new-name", %{"value" => v}, socket) do
    {:noreply, assign(socket, new_name: v)}
  end

  @impl true
  def handle_event("set-new-desc", %{"value" => v}, socket) do
    {:noreply, assign(socket, new_desc: v)}
  end

  @impl true
  def handle_event("toggle-public", _, socket) do
    {:noreply, assign(socket, new_public: !socket.assigns.new_public)}
  end

  @impl true
  def handle_event("create-project", _params, socket) do
    user = socket.assigns.current_user

    attrs = %{
      "name"        => socket.assigns.new_name,
      "description" => socket.assigns.new_desc,
      "is_public"   => socket.assigns.new_public,
      "tags"        => [],
      "license"     => "ofl"
    }

    case Fonts.create_project(attrs, user.id) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(show_new_modal: false, new_name: "", new_desc: "")
         |> push_navigate(to: "/studio/#{project.id}")}

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
          |> Enum.join("; ")
        {:noreply, assign(socket, form_error: errors)}
    end
  end

  defp visibility_badge(true),  do: {"Public",  "#1e3a5f", "#60a5fa"}
  defp visibility_badge(false), do: {"Private", "#1e1b4b", "#a78bfa"}

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)
    cond do
      diff < 60     -> "just now"
      diff < 3600   -> "#{div(diff, 60)}m ago"
      diff < 86400  -> "#{div(diff, 3600)}h ago"
      diff < 604800 -> "#{div(diff, 86400)}d ago"
      true          -> Calendar.strftime(dt, "%b %d, %Y")
    end
  end
  defp relative_time(_), do: "—"

  @impl true
  def render(assigns) do
    ~H"""
    <div style="min-height:100vh;">

      <%# ── Studio header ─────────────────────────────────────────────────── %>
      <div style="border-bottom:1px solid rgba(255,255,255,.06);background:rgba(19,19,31,.6);padding:2.5rem 1.5rem 1.5rem;">
        <div style="max-width:1280px;margin:0 auto;display:flex;align-items:flex-start;justify-content:space-between;flex-wrap:wrap;gap:1.5rem;">
          <div>
            <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:.4rem;">
              <div style="width:34px;height:34px;border-radius:50%;background:linear-gradient(135deg,#7c3aed,#06b6d4);display:flex;align-items:center;justify-content:center;font-size:.85rem;font-weight:700;color:#fff;flex-shrink:0;">
                <%= String.first(@current_user.username) |> String.upcase() %>
              </div>
              <h1 style="font-size:1.5rem;font-weight:800;letter-spacing:-.025em;">
                <%= @current_user.username %>'s Studio
              </h1>
            </div>
            <p style="color:#64748b;font-size:.875rem;margin-left:2.9rem;"><%= @current_user.bio || "Font designer" %></p>
          </div>

          <button
            phx-click="open-new-modal"
            style="display:flex;align-items:center;gap:.5rem;padding:.65rem 1.3rem;background:#7c3aed;border:none;border-radius:9px;color:#fff;font-size:.875rem;font-weight:600;cursor:pointer;"
            onmouseover="this.style.background='#6d28d9'" onmouseout="this.style.background='#7c3aed'"
          >
            <span style="font-size:1.1rem;line-height:1;">+</span> New project
          </button>
        </div>

        <%# Stats row %>
        <div style="max-width:1280px;margin:.75rem auto 0;display:flex;gap:2.5rem;flex-wrap:wrap;">
          <%= for {label, val} <- [{"Projects", length(@projects)}, {"Font files", @total_fonts}, {"Downloads", @total_downloads}] do %>
            <div>
              <span style="font-size:1.4rem;font-weight:700;background:linear-gradient(135deg,#a78bfa,#67e8f9);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;"><%= val %></span>
              <span style="font-size:.78rem;color:#475569;margin-left:.35rem;"><%= label %></span>
            </div>
          <% end %>
        </div>
      </div>

      <%# ── Project grid ────────────────────────────────────────────────────── %>
      <div style="max-width:1280px;margin:2rem auto;padding:0 1.5rem;">

        <%= if length(@projects) == 0 do %>
          <div style="text-align:center;padding:6rem 2rem;border:1px dashed rgba(255,255,255,.08);border-radius:16px;">
            <div style="font-size:3rem;margin-bottom:1rem;opacity:.3;">◈</div>
            <p style="color:#64748b;font-size:1rem;margin-bottom:.5rem;">No projects yet</p>
            <p style="color:#475569;font-size:.85rem;margin-bottom:1.5rem;">Create your first typeface project to get started.</p>
            <button phx-click="open-new-modal" style="padding:.65rem 1.5rem;background:#7c3aed;border:none;border-radius:8px;color:#fff;font-size:.875rem;font-weight:600;cursor:pointer;">
              Create first project
            </button>
          </div>
        <% else %>
          <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:1.2rem;">
            <%= for {project, idx} <- Enum.with_index(@projects) do %>
              <% {vis_label, vis_bg, vis_color} = visibility_badge(project.is_public) %>
              <a
                href={"/studio/#{project.id}"}
                style={"display:block;text-decoration:none;background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:14px;overflow:hidden;transition:all .2s;animation:fadeUp .3s #{idx * 40}ms both ease;"}
                onmouseover="this.style.borderColor='rgba(124,58,237,.3)';this.style.transform='translateY(-2px)';this.style.boxShadow='0 10px 28px rgba(0,0,0,.45)'"
                onmouseout="this.style.borderColor='rgba(255,255,255,.07)';this.style.transform='translateY(0)';this.style.boxShadow='none'"
              >
                <%# Cover preview %>
                <div style="height:88px;background:linear-gradient(135deg,#1a1a2e 0%,#13131f 100%);display:flex;align-items:center;padding:0 1.25rem;border-bottom:1px solid rgba(255,255,255,.05);position:relative;">
                  <span style="font-size:2.6rem;font-weight:800;letter-spacing:-.04em;color:rgba(255,255,255,.1);font-family:serif;">Aa</span>
                  <span style="font-size:1.8rem;font-weight:400;letter-spacing:-.02em;color:rgba(255,255,255,.06);margin-left:.5rem;">Bb Cc</span>
                  <div style={"position:absolute;top:.6rem;right:.65rem;padding:.15rem .55rem;border-radius:100px;font-size:.62rem;font-weight:700;letter-spacing:.03em;background:#{vis_bg};color:#{vis_color};"}>
                    <%= vis_label %>
                  </div>
                </div>

                <%# Info %>
                <div style="padding:1.1rem 1.2rem 1.2rem;">
                  <div style="font-weight:700;font-size:.95rem;margin-bottom:.3rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#e2e8f0;">
                    <%= project.name %>
                  </div>
                  <div style="font-size:.8rem;color:#64748b;margin-bottom:.9rem;line-height:1.45;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;">
                    <%= project.description || "No description." %>
                  </div>
                  <div style="display:flex;align-items:center;justify-content:space-between;">
                    <div style="font-size:.72rem;color:#475569;">
                      <%= length(project.font_files || []) %> font<%= if length(project.font_files || []) != 1, do: "s" %>
                    </div>
                    <div style="font-size:.72rem;color:#475569;">
                      <%= relative_time(project.updated_at) %>
                    </div>
                  </div>
                </div>
              </a>
            <% end %>
          </div>
        <% end %>
      </div>

      <%# ── New project modal ────────────────────────────────────────────── %>
      <%= if @show_new_modal do %>
        <div style="position:fixed;inset:0;background:rgba(0,0,0,.7);backdrop-filter:blur(4px);z-index:100;display:flex;align-items:center;justify-content:center;padding:1rem;">
          <div style="background:#13131f;border:1px solid rgba(255,255,255,.1);border-radius:18px;padding:2rem;width:100%;max-width:460px;" phx-click-away="close-modal">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:1.5rem;">
              <h2 style="font-size:1.2rem;font-weight:700;letter-spacing:-.02em;">New project</h2>
              <button phx-click="close-modal" style="color:#64748b;background:none;border:none;font-size:1.3rem;cursor:pointer;line-height:1;">×</button>
            </div>

            <%= if @form_error do %>
              <div style="background:#3b1219;border:1px solid rgba(252,165,165,.2);border-radius:8px;padding:.65rem .9rem;color:#fca5a5;font-size:.8rem;margin-bottom:1rem;">
                <%= @form_error %>
              </div>
            <% end %>

            <div style="display:flex;flex-direction:column;gap:1.1rem;">
              <div>
                <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Project name *</label>
                <input
                  type="text"
                  value={@new_name}
                  placeholder="Neue Grotesk Variable"
                  phx-keyup="set-new-name"
                  style="width:100%;padding:.7rem 1rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;"
                  onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"
                />
              </div>

              <div>
                <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Description</label>
                <textarea
                  placeholder="A clean variable typeface designed for editorial contexts…"
                  phx-keyup="set-new-desc"
                  rows="3"
                  style="width:100%;padding:.7rem 1rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;resize:vertical;"
                  onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"
                ><%= @new_desc %></textarea>
              </div>

              <div style="display:flex;align-items:center;justify-content:space-between;padding:.75rem 1rem;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.07);border-radius:9px;">
                <div>
                  <p style="font-size:.875rem;font-weight:500;">Publish to gallery</p>
                  <p style="font-size:.75rem;color:#64748b;margin-top:.15rem;">Make this project visible to everyone</p>
                </div>
                <div
                  phx-click="toggle-public"
                  style={"width:42px;height:24px;border-radius:100px;cursor:pointer;transition:background .2s;position:relative;flex-shrink:0;" <> if @new_public, do: "background:#7c3aed;", else: "background:#334155;"}
                >
                  <div style={"width:18px;height:18px;border-radius:50%;background:#fff;position:absolute;top:3px;transition:left .2s;" <> if @new_public, do: "left:21px;", else: "left:3px;"}></div>
                </div>
              </div>

              <div style="display:flex;gap:.75rem;margin-top:.25rem;">
                <button phx-click="close-modal" style="flex:1;padding:.75rem;background:transparent;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#94a3b8;font-size:.875rem;cursor:pointer;">
                  Cancel
                </button>
                <button phx-click="create-project" disabled={@new_name == ""}
                  style={"flex:2;padding:.75rem;border:none;border-radius:9px;color:#fff;font-size:.875rem;font-weight:600;cursor:pointer;" <> if @new_name != "", do: "background:#7c3aed;", else: "background:#334155;opacity:.5;cursor:not-allowed;"}>
                  Create project
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

    </div>
    """
  end
end
