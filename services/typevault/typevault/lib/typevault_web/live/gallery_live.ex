defmodule TypeVaultWeb.GalleryLive do
  use TypeVaultWeb, :live_view

  alias TypeVault.Gallery

  on_mount {TypeVaultWeb.Live.Auth, :load_current_user}

  @sort_fields ~w(downloads rating name inserted_at)

  @impl true
  def mount(_params, _session, socket) do
    fonts = Gallery.list_public_fonts(%{
      "sort_by"  => "downloads",
      "sort_dir" => "DESC",
      "limit"    => "24"
    })

    tags = Gallery.get_popular_tags()

    {:ok,
     assign(socket,
       page_title:   "Font Gallery",
       fonts:        fonts,
       search:       "",
       sort_by:      "downloads",
       sort_dir:     "DESC",
       active_tags:  [],
       all_tags:     tags,
       loading:      false,
       conn_or_lv_path: "/gallery"
     )}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    fonts = reload(socket, search: q)
    {:noreply, assign(socket, fonts: fonts, search: q)}
  end

  @impl true
  def handle_event("sort-by", %{"field" => field}, socket) when field in @sort_fields do
    dir   = if field == socket.assigns.sort_by, do: flip(socket.assigns.sort_dir), else: "DESC"
    fonts = reload(socket, sort_by: field, sort_dir: dir)
    {:noreply, assign(socket, fonts: fonts, sort_by: field, sort_dir: dir)}
  end

  @impl true
  def handle_event("toggle-tag", %{"tag" => tag}, socket) do
    tags =
      if tag in socket.assigns.active_tags,
        do:   Enum.reject(socket.assigns.active_tags, &(&1 == tag)),
        else: [tag | socket.assigns.active_tags]

    fonts = reload(socket, active_tags: tags)
    {:noreply, assign(socket, fonts: fonts, active_tags: tags)}
  end

  @impl true
  def handle_event("clear-filters", _, socket) do
    fonts = Gallery.list_public_fonts(%{
      "sort_by"  => socket.assigns.sort_by,
      "sort_dir" => socket.assigns.sort_dir,
      "limit"    => "24"
    })
    {:noreply, assign(socket, fonts: fonts, search: "", active_tags: [])}
  end

  defp reload(socket, overrides) do
    a = socket.assigns
    params =
      %{
        "sort_by"  => Keyword.get(overrides, :sort_by, a.sort_by),
        "sort_dir" => Keyword.get(overrides, :sort_dir, a.sort_dir),
        "search"   => Keyword.get(overrides, :search, a.search),
        "tags"     => Keyword.get(overrides, :active_tags, a.active_tags),
        "limit"    => "48"
      }
    # Keep sorting options aligned with UI toggles; backend normalizes direction.
    Gallery.list_public_fonts(params)
  end

  defp flip("DESC"), do: "ASC"
  defp flip(_),      do: "DESC"

  defp sort_icon(field, field, "DESC"), do: "↓"
  defp sort_icon(field, field, "ASC"),  do: "↑"
  defp sort_icon(_, _, _),              do: "↕"

  defp format_count(n) when n >= 1000, do: "#{div(n, 1000)}k"
  defp format_count(n), do: to_string(n)

  defp license_badge("ofl"),        do: {"OFL", "#166534", "#4ade80"}
  defp license_badge("apache"),     do: {"Apache", "#1e3a5f", "#60a5fa"}
  defp license_badge("cc-by"),      do: {"CC BY", "#3b2f00", "#fbbf24"}
  defp license_badge("proprietary"),do: {"©",     "#1e1b4b", "#a78bfa"}
  defp license_badge(_),            do: {"Free",  "#14374e", "#67e8f9"}

  defp preview_letters, do: ["Aa", "Gg", "Rr", "Ss", "Tt", "Qq"]

  @impl true
  def render(assigns) do
    ~H"""
    <div style="min-height:100vh;">

      <%# ── Hero bar ──────────────────────────────────────────────────────── %>
      <div style="background:linear-gradient(180deg,rgba(124,58,237,.08) 0%,transparent 100%);border-bottom:1px solid rgba(255,255,255,.06);padding:3rem 1.5rem 2rem;">
        <div style="max-width:1280px;margin:0 auto;">
          <div style="display:flex;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;gap:1.5rem;">
            <div>
              <p style="font-size:.72rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:#a78bfa;margin-bottom:.5rem;">Community</p>
              <h1 style="font-size:clamp(1.75rem,4vw,2.5rem);font-weight:800;letter-spacing:-.03em;margin-bottom:.5rem;">Font Gallery</h1>
              <p style="color:#64748b;font-size:.95rem;"><%= length(@fonts) %> typefaces published by designers worldwide</p>
            </div>

            <%# Search %>
            <div style="position:relative;width:min(100%,340px);">
              <span style="position:absolute;left:.85rem;top:50%;transform:translateY(-50%);color:#475569;font-size:1rem;pointer-events:none;">⌕</span>
              <input
                type="text"
                value={@search}
                placeholder="Search typefaces…"
                phx-keyup="search"
                phx-debounce="280"
                name="q"
                style="width:100%;padding:.7rem 1rem .7rem 2.4rem;background:#13131f;border:1px solid rgba(255,255,255,.1);border-radius:10px;color:#e2e8f0;font-size:.9rem;outline:none;"
                onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"
              />
            </div>
          </div>
        </div>
      </div>

      <div style="max-width:1280px;margin:0 auto;padding:2rem 1.5rem;">

        <%# ── Controls bar ───────────────────────────────────────────────── %>
        <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:1rem;margin-bottom:1.5rem;">

          <%# Tag chips %>
          <div style="display:flex;flex-wrap:wrap;gap:.4rem;align-items:center;">
            <%= for tag <- Enum.take(@all_tags, 12) do %>
              <button
                phx-click="toggle-tag"
                phx-value-tag={tag}
                class={"tag-chip#{if tag in @active_tags, do: " active", else: ""}"}
              ><%= tag %></button>
            <% end %>
            <%= if length(@active_tags) > 0 do %>
              <button phx-click="clear-filters" style="color:#ef4444;font-size:.72rem;margin-left:.25rem;background:none;border:none;cursor:pointer;">✕ Clear</button>
            <% end %>
          </div>

          <%# Sort buttons %>
          <div style="display:flex;align-items:center;gap:.35rem;">
            <span style="color:#475569;font-size:.78rem;margin-right:.25rem;">Sort:</span>
            <%= for {label, field} <- [{"Downloads", "downloads"}, {"Rating", "rating"}, {"Name", "name"}, {"Newest", "inserted_at"}] do %>
              <button
                phx-click="sort-by"
                phx-value-field={field}
                style={"padding:.3rem .75rem;border-radius:6px;font-size:.78rem;cursor:pointer;border:1px solid rgba(255,255,255,.08);transition:all .15s;" <> if field == @sort_by, do: "background:rgba(124,58,237,.2);color:#a78bfa;border-color:rgba(124,58,237,.35);", else: "background:transparent;color:#64748b;"}
              ><%= label %> <%= sort_icon(field, @sort_by, @sort_dir) %></button>
            <% end %>
          </div>
        </div>

        <%# ── Font grid ──────────────────────────────────────────────────── %>
        <%= if length(@fonts) == 0 do %>
          <div style="text-align:center;padding:5rem 2rem;color:#475569;">
            <div style="font-size:3rem;margin-bottom:1rem;opacity:.4;">◈</div>
            <p style="font-size:1rem;margin-bottom:.5rem;color:#64748b;">No typefaces found</p>
            <p style="font-size:.85rem;">Try adjusting your search or filters.</p>
          </div>
        <% else %>
          <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:1.2rem;">
            <%= for {font, idx} <- Enum.with_index(@fonts) do %>
              <% {lic_text, lic_bg, lic_color} = license_badge(font.license) %>
              <a
                href={"/studio/#{font.id}"}
                style={"display:block;text-decoration:none;color:inherit;background:#13131f;border:1px solid rgba(255,255,255,.07);border-radius:14px;overflow:hidden;cursor:pointer;transition:all .2s;animation:fadeUp .3s #{idx * 30}ms both ease;"}
                onmouseover="this.style.borderColor='rgba(124,58,237,.35)';this.style.transform='translateY(-3px)';this.style.boxShadow='0 12px 32px rgba(0,0,0,.5)'"
                onmouseout="this.style.borderColor='rgba(255,255,255,.07)';this.style.transform='translateY(0)';this.style.boxShadow='none'"
              >
                <%# Preview area %>
                <div style="height:100px;background:linear-gradient(135deg,#1a1a2e,#13131f);display:flex;align-items:center;justify-content:center;position:relative;overflow:hidden;border-bottom:1px solid rgba(255,255,255,.05);">
                  <span style="font-size:2.8rem;font-weight:800;letter-spacing:-.04em;color:rgba(255,255,255,.15);user-select:none;">
                    <%= Enum.at(preview_letters(), rem(idx, 6)) %>
                  </span>
                  <div style={"position:absolute;top:.6rem;right:.6rem;padding:.18rem .55rem;border-radius:100px;font-size:.62rem;font-weight:700;letter-spacing:.04em;background:#{lic_bg};color:#{lic_color};"}>
                    <%= lic_text %>
                  </div>
                </div>

                <%# Info %>
                <div style="padding:1rem 1.1rem 1.1rem;">
                  <div style="font-weight:600;font-size:.93rem;margin-bottom:.2rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">
                    <%= font.name %>
                  </div>
                  <%= if font[:author] do %>
                    <div style="font-size:.72rem;color:#7c3aed;margin-bottom:.35rem;">by <%= font.author %></div>
                  <% end %>
                  <div style="display:flex;justify-content:space-between;align-items:center;">
                    <div style="display:flex;gap:.6rem;">
                      <%= for tag <- Enum.take(font.tags || [], 2) do %>
                        <span style="font-size:.68rem;color:#64748b;background:rgba(255,255,255,.04);padding:.1rem .45rem;border-radius:4px;"><%= tag %></span>
                      <% end %>
                    </div>
                    <div style="display:flex;align-items:center;gap:.7rem;">
                      <span style="font-size:.75rem;color:#475569;"><%= format_count(font.downloads || 0) %> ↓</span>
                      <span
                        onclick={"event.preventDefault(); window.location='/studio/#{font.id}'"}
                        style="font-size:.7rem;padding:.2rem .6rem;background:rgba(124,58,237,.18);border:1px solid rgba(124,58,237,.35);border-radius:6px;color:#c4b5fd;font-weight:600;cursor:pointer;"
                      >Get</span>
                    </div>
                  </div>
                </div>
              </a>
            <% end %>
          </div>
        <% end %>

      </div>
    </div>
    """
  end
end
