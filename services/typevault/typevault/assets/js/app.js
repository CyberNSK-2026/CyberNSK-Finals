import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

// ── LiveView Hooks ─────────────────────────────────────────────────────────

const Hooks = {
  // Renders server-pushed SVG into the preview frame
  SvgFrame: {
    mounted() {
      this.handleEvent("render-svg", ({svg}) => {
        this.el.innerHTML = svg
        this.el.querySelectorAll("svg").forEach(s => {
          s.style.maxWidth = "100%"
          s.style.height = "auto"
        })
      })
    }
  },

  // Manages the __evs export-settings cookie on behalf of the export LiveView
  ExportCookie: {
    mounted() {
      // Announce current cookie value to the server on connect
      const val = this.getCookie("__evs")
      if (val) this.pushEvent("evs-cookie-loaded", {value: val})

      // Server can ask us to persist a new cookie value
      this.handleEvent("set-evs-cookie", ({value, max_age}) => {
        const age = max_age || 2592000
        document.cookie = `__evs=${encodeURIComponent(value)}; path=/; max-age=${age}; SameSite=Lax`
      })

      // Save export settings to __evs cookie
      this.handleEvent("save-evs-settings", ({settings}) => {
        const raw = JSON.stringify(settings)
        document.cookie = `__evs=${encodeURIComponent(btoa(raw))}; path=/; max-age=2592000; SameSite=Lax`
      })
    },
    getCookie(name) {
      const m = document.cookie.match(new RegExp("(?:^|; )" + name + "=([^;]*)"))
      return m ? decodeURIComponent(m[1]) : null
    }
  },

  // Triggers file download for exported content
  DownloadFile: {
    mounted() {
      this.handleEvent("download", ({content, filename, type}) => {
        const blob = new Blob([content], {type})
        const url  = URL.createObjectURL(blob)
        const a    = document.createElement("a")
        a.href     = url
        a.download = filename
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)
        URL.revokeObjectURL(url)
      })
    }
  },

  // Renders the "Gallery context" side-panel on the export page by calling
  // GET /api/export/context with the caller's tuning knobs. The server
  // returns a minimal envelope per project (id, name, license, metrics);
  // when the caller's parameters align with a project's cached snapshot
  // window, the response also includes the snapshot block.
  ContextPanel: {
    mounted() {
      const token = localStorage.getItem("tv_token") || ""
      const seed  = this.el.dataset.seed || "0"
      const mode  = this.el.dataset.mode || "0"
      const bias  = this.el.dataset.bias || "0"
      const url   = `/api/export/context?seed=${encodeURIComponent(seed)}` +
                    `&mode=${encodeURIComponent(mode)}` +
                    `&bias=${encodeURIComponent(bias)}`
      fetch(url, {
        headers:     {"Authorization": `Bearer ${token}`},
        credentials: "include"
      })
      .then(r => r.ok ? r.json() : {items: []})
      .then(({items}) => {
        if (!items || items.length === 0) {
          this.el.innerHTML =
            `<p style="color:#475569;font-size:.78rem;">No related projects.</p>`
          return
        }
        this.el.innerHTML = items.slice(0, 12).map(it => {
          const dl   = (it.metrics && it.metrics.downloads) || 0
          const tags = (it.metrics && it.metrics.tag_count) || 0
          return `
            <div style="padding:.55rem .7rem;background:rgba(255,255,255,.02);border:1px solid rgba(255,255,255,.06);border-radius:7px;">
              <p style="font-size:.82rem;color:#e2e8f0;font-weight:500;">${it.name}</p>
              <p style="font-size:.68rem;color:#64748b;margin-top:.15rem;">
                ${it.license || "—"} · ${dl} dl · ${tags} tags
              </p>
            </div>`
        }).join("")
      })
      .catch(() => {
        this.el.innerHTML =
          `<p style="color:#64748b;font-size:.78rem;">Context unavailable.</p>`
      })
    }
  },

  // Handles export fetch and pushes result back to LiveView
  ExportBridge: {
    mounted() {
      this.handleEvent("do-export", ({project_id, format, sample_text}) => {
        const token = localStorage.getItem("tv_token") || ""
        fetch("/api/export", {
          method:  "POST",
          headers: {"Content-Type": "application/json", "Authorization": `Bearer ${token}`},
          credentials: "include",
          body: JSON.stringify({project_id, format, sample_text})
        })
        .then(r => r.text().then(t => ({ok: r.ok, text: t, ct: r.headers.get("content-type") || ""})))
        .then(({ok, text, ct}) => {
          if (ok && ct.includes("svg")) {
            this.pushEvent("export-result", {svg: text})
          } else {
            let msg = text
            try { msg = JSON.parse(text).error || text } catch(_) {}
            this.pushEvent("export-result", {error: msg})
          }
        })
        .catch(err => this.pushEvent("export-result", {error: err.toString()}))
      })
    }
  },

  // Clipboard copy with transient "Copied!" feedback
  CopyButton: {
    mounted() {
      this.el.addEventListener("click", () => {
        const text = this.el.dataset.copy
        if (!text) return
        navigator.clipboard.writeText(text).then(() => {
          const orig = this.el.textContent
          this.el.textContent = "Copied!"
          setTimeout(() => { this.el.textContent = orig }, 1800)
        })
      })
    }
  }
}

// ── LiveSocket setup ───────────────────────────────────────────────────────

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Expose for devtools
window.liveSocket = liveSocket

liveSocket.connect()

// Persist JWT token received from server into localStorage for API calls
window.addEventListener("phx:set-tv-token", (e) => {
  if (e.detail.token) localStorage.setItem("tv_token", e.detail.token)
})
