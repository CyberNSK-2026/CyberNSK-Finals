defmodule TypeVaultWeb.PageController do
  use TypeVaultWeb, :controller

  @doc "GET / — marketing landing page"
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, landing_html())
  end

  # ── HTML ──────────────────────────────────────────────────────────────────

  defp landing_html do
    ~S"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TypeVault — Professional Font Design Platform</title>
  <style>
    :root {
      --bg:      #09090f;
      --surf:    #13131f;
      --surf2:   #1a1a2e;
      --border:  rgba(255,255,255,0.06);
      --pri:     #7c3aed;
      --pri-lt:  #a78bfa;
      --acc:     #06b6d4;
      --txt:     #e2e8f0;
      --muted:   #64748b;
      --glow:    rgba(124,58,237,0.14);
    }
    *, *::before, *::after { margin:0; padding:0; box-sizing:border-box; }
    html { scroll-behavior:smooth; }
    body {
      background:var(--bg); color:var(--txt);
      font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
      line-height:1.6; overflow-x:hidden;
    }

    /* ── NAV ── */
    nav {
      position:fixed; inset:0 0 auto; z-index:100;
      background:rgba(9,9,15,.85); backdrop-filter:blur(24px);
      border-bottom:1px solid var(--border);
    }
    .nav-in {
      max-width:1200px; margin:0 auto; height:64px;
      display:flex; align-items:center; justify-content:space-between;
      padding:0 2rem;
    }
    .logo {
      font-size:1.15rem; font-weight:800; letter-spacing:-.03em;
      background:linear-gradient(135deg,var(--pri-lt),var(--acc));
      -webkit-background-clip:text; -webkit-text-fill-color:transparent;
      background-clip:text; text-decoration:none;
    }
    .nav-links { display:flex; gap:2rem; list-style:none; }
    .nav-links a { color:var(--muted); text-decoration:none; font-size:.9rem; transition:color .2s; }
    .nav-links a:hover { color:var(--txt); }
    .nav-acts { display:flex; gap:.75rem; align-items:center; }
    .btn {
      padding:.45rem 1.1rem; border-radius:8px; font-size:.875rem; font-weight:500;
      cursor:pointer; border:none; text-decoration:none; transition:all .2s;
      display:inline-flex; align-items:center; gap:.4rem;
    }
    .btn-ghost {
      background:transparent; color:var(--muted);
      border:1px solid var(--border);
    }
    .btn-ghost:hover { color:var(--txt); border-color:rgba(255,255,255,.15); background:rgba(255,255,255,.04); }
    .btn-pri { background:var(--pri); color:#fff; }
    .btn-pri:hover { background:#6d28d9; transform:translateY(-1px); box-shadow:0 8px 24px rgba(124,58,237,.4); }

    /* ── HERO ── */
    .hero {
      min-height:100vh; display:flex; align-items:center; justify-content:center;
      position:relative; padding:8rem 2rem 5rem; overflow:hidden;
    }
    .hero-bg {
      position:absolute; inset:0;
      background:
        radial-gradient(ellipse 80% 50% at 50% -15%, rgba(124,58,237,.18) 0%, transparent 65%),
        radial-gradient(ellipse 55% 40% at 80% 90%, rgba(6,182,212,.07) 0%, transparent 60%);
    }
    .glyph {
      position:absolute; font-weight:900; opacity:.025; user-select:none;
      pointer-events:none; animation:drift linear infinite;
    }
    @keyframes drift {
      0%   { transform:translateY(0)    rotate(0deg);  }
      33%  { transform:translateY(-28px) rotate(6deg); }
      66%  { transform:translateY(14px)  rotate(-4deg);}
      100% { transform:translateY(0)    rotate(0deg);  }
    }
    .hero-cnt { position:relative; text-align:center; max-width:780px; z-index:1; }
    .badge {
      display:inline-flex; align-items:center; gap:.5rem;
      background:rgba(124,58,237,.1); border:1px solid rgba(124,58,237,.22);
      color:var(--pri-lt); padding:.3rem 1rem; border-radius:100px;
      font-size:.78rem; font-weight:600; letter-spacing:.04em; margin-bottom:1.5rem;
    }
    .hero h1 {
      font-size:clamp(2.8rem,7vw,5rem); font-weight:800;
      letter-spacing:-.035em; line-height:1.06; margin-bottom:1.25rem;
    }
    .grad {
      background:linear-gradient(135deg,#a78bfa 0%,#818cf8 45%,#38bdf8 100%);
      -webkit-background-clip:text; -webkit-text-fill-color:transparent; background-clip:text;
    }
    .hero p { font-size:1.15rem; color:var(--muted); margin-bottom:2.5rem; max-width:500px; margin-left:auto; margin-right:auto; }
    .hero-btns { display:flex; gap:1rem; justify-content:center; flex-wrap:wrap; }
    .btn-cta {
      background:linear-gradient(135deg,var(--pri),#5b21b6); color:#fff;
      padding:.9rem 2.2rem; font-size:1rem; font-weight:600; border-radius:10px;
      border:none; cursor:pointer; text-decoration:none;
      display:inline-flex; align-items:center; gap:.5rem;
      transition:all .3s; animation:pulse-glow 3s ease-in-out infinite;
    }
    .btn-cta:hover { transform:translateY(-2px); box-shadow:0 14px 32px rgba(124,58,237,.5); animation:none; }
    @keyframes pulse-glow {
      0%,100% { box-shadow:0 0 18px rgba(124,58,237,.28); }
      50%     { box-shadow:0 0 36px rgba(124,58,237,.48); }
    }
    .btn-out {
      background:transparent; color:var(--txt); padding:.9rem 2.2rem; font-size:1rem;
      font-weight:500; border-radius:10px; border:1px solid rgba(255,255,255,.12);
      cursor:pointer; text-decoration:none; display:inline-flex; align-items:center; gap:.5rem;
      transition:all .2s;
    }
    .btn-out:hover { background:rgba(255,255,255,.04); border-color:rgba(255,255,255,.2); }
    .scroll-hint {
      position:absolute; bottom:2.5rem; left:50%; transform:translateX(-50%);
      display:flex; flex-direction:column; align-items:center; gap:.5rem;
      color:var(--muted); font-size:.75rem;
      animation:bob 2.4s ease-in-out infinite;
    }
    @keyframes bob {
      0%,100% { transform:translateX(-50%) translateY(0); }
      50%     { transform:translateX(-50%) translateY(8px); }
    }
    .scroll-arrow { width:22px; height:22px; border-right:2px solid var(--muted); border-bottom:2px solid var(--muted); transform:rotate(45deg); }

    /* ── STATS BAR ── */
    .stats-bar { background:var(--surf2); border-top:1px solid var(--border); border-bottom:1px solid var(--border); }
    .stats-in {
      max-width:1200px; margin:0 auto; padding:2.25rem 2rem;
      display:flex; justify-content:space-around; flex-wrap:wrap; gap:1.5rem;
    }
    .stat { text-align:center; }
    .stat-val {
      font-size:2rem; font-weight:700;
      background:linear-gradient(135deg,var(--pri-lt),var(--acc));
      -webkit-background-clip:text; -webkit-text-fill-color:transparent; background-clip:text;
    }
    .stat-lbl { font-size:.82rem; color:var(--muted); margin-top:.2rem; }

    /* ── SECTION ── */
    .sec { padding:5.5rem 2rem; }
    .sec-in { max-width:1200px; margin:0 auto; }
    .sec-hd { text-align:center; margin-bottom:3.5rem; }
    .sec-lbl { font-size:.78rem; font-weight:700; letter-spacing:.12em; text-transform:uppercase; color:var(--pri-lt); margin-bottom:.6rem; }
    .sec-ttl { font-size:clamp(1.8rem,4vw,2.7rem); font-weight:700; letter-spacing:-.025em; margin-bottom:.9rem; }
    .sec-sub { color:var(--muted); font-size:1.05rem; max-width:500px; margin:0 auto; }

    /* ── FEATURES ── */
    .feat-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(255px,1fr)); gap:1.4rem; }
    .feat-card {
      background:var(--surf); border:1px solid var(--border); border-radius:16px; padding:1.75rem;
      transition:all .3s; position:relative; overflow:hidden;
    }
    .feat-card::after {
      content:''; position:absolute; inset:0;
      background:linear-gradient(135deg,var(--glow),transparent); opacity:0; transition:opacity .3s;
    }
    .feat-card:hover { border-color:rgba(124,58,237,.28); transform:translateY(-4px); box-shadow:0 16px 40px rgba(0,0,0,.38); }
    .feat-card:hover::after { opacity:1; }
    .feat-icon {
      width:46px; height:46px; background:rgba(124,58,237,.14); border-radius:11px;
      display:flex; align-items:center; justify-content:center;
      font-size:1.3rem; margin-bottom:1.1rem;
    }
    .feat-card h3 { font-size:1.05rem; font-weight:600; margin-bottom:.5rem; }
    .feat-card p { color:var(--muted); font-size:.875rem; line-height:1.65; }

    /* ── GALLERY ── */
    .gallery-sec { background:var(--surf); border-top:1px solid var(--border); border-bottom:1px solid var(--border); }
    .font-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(270px,1fr)); gap:1.4rem; }
    .font-card {
      background:var(--bg); border:1px solid var(--border); border-radius:14px;
      overflow:hidden; cursor:pointer; transition:all .25s;
      opacity:0; transform:translateY(18px);
    }
    .font-card.show { opacity:1; transform:translateY(0); transition:opacity .4s ease, transform .4s ease, border-color .25s, box-shadow .25s; }
    .font-card:hover { border-color:rgba(124,58,237,.3); box-shadow:0 8px 28px rgba(0,0,0,.45); }
    .font-prev {
      background:var(--surf2); height:96px;
      display:flex; align-items:center; justify-content:center;
      font-size:2.6rem; font-weight:700; letter-spacing:-.03em;
      color:rgba(255,255,255,.12); overflow:hidden; position:relative;
    }
    .font-prev::before {
      content:''; position:absolute; inset:0;
      background:linear-gradient(135deg,rgba(124,58,237,.06),rgba(6,182,212,.04));
    }
    .font-body { padding:1.1rem 1.2rem; }
    .font-name { font-weight:600; font-size:.93rem; margin-bottom:.3rem; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
    .font-meta { font-size:.78rem; color:var(--muted); display:flex; gap:.75rem; }
    .gallery-load {
      display:flex; align-items:center; justify-content:center;
      padding:3rem; color:var(--muted); font-size:.9rem; gap:.75rem;
    }
    .spin {
      width:20px; height:20px; border:2px solid var(--border); border-top-color:var(--pri);
      border-radius:50%; animation:rotate .7s linear infinite; flex-shrink:0;
    }
    @keyframes rotate { to { transform:rotate(360deg); } }
    .gallery-more { text-align:center; margin-top:2.5rem; }

    /* ── CTA ── */
    .cta-sec { text-align:center; }
    .cta-card {
      background:linear-gradient(135deg,rgba(124,58,237,.1),rgba(6,182,212,.05));
      border:1px solid rgba(124,58,237,.18); border-radius:24px; padding:4.5rem 2rem;
      position:relative; overflow:hidden;
    }
    .cta-card::before {
      content:''; position:absolute; width:700px; height:700px;
      background:radial-gradient(circle,rgba(124,58,237,.1) 0%,transparent 70%);
      top:50%; left:50%; transform:translate(-50%,-50%); pointer-events:none;
    }
    .cta-card h2 { font-size:clamp(1.8rem,4vw,2.5rem); font-weight:700; letter-spacing:-.025em; margin-bottom:.9rem; position:relative; }
    .cta-card p  { color:var(--muted); margin-bottom:2.5rem; font-size:1.05rem; position:relative; }

    /* ── FOOTER ── */
    footer { border-top:1px solid var(--border); padding:2.5rem 2rem; }
    .foot-in {
      max-width:1200px; margin:0 auto;
      display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:1rem;
    }
    .foot-in p { color:var(--muted); font-size:.82rem; }
    .foot-links { display:flex; gap:1.5rem; list-style:none; }
    .foot-links a { color:var(--muted); text-decoration:none; font-size:.82rem; transition:color .2s; }
    .foot-links a:hover { color:var(--txt); }

    /* ── ANIMATIONS ── */
    .fi { opacity:0; transform:translateY(22px); transition:opacity .6s ease, transform .6s ease; }
    .fi.show { opacity:1; transform:translateY(0); }

    /* ── SVG DRAW ANIMATION ── */
    .glyph-draw { position:absolute; right:8%; top:50%; transform:translateY(-50%); opacity:.07; pointer-events:none; }
    .glyph-draw path { stroke-dasharray:1200; stroke-dashoffset:1200; animation:draw 6s ease forwards 1s; }
    @keyframes draw { to { stroke-dashoffset:0; } }

    @media(max-width:768px) {
      .nav-links { display:none; }
      .stats-in  { justify-content:center; }
      .glyph-draw { display:none; }
    }
  </style>
</head>
<body>

<!-- NAV -->
<nav>
  <div class="nav-in">
    <a class="logo" href="/">TypeVault</a>
    <ul class="nav-links">
      <li><a href="#features">Features</a></li>
      <li><a href="#gallery">Gallery</a></li>
      <li><a href="/api/gallery">API</a></li>
    </ul>
    <div class="nav-acts">
      <a class="btn btn-ghost" href="/login">Sign in</a>
      <a class="btn btn-pri" href="/register">Get started</a>
    </div>
  </div>
</nav>

<!-- HERO -->
<section class="hero">
  <div class="hero-bg"></div>

  <span class="glyph" style="font-size:clamp(5rem,12vw,11rem);left:3%;top:12%;animation-duration:20s">A</span>
  <span class="glyph" style="font-size:clamp(4rem,9vw,9rem);right:5%;top:18%;animation-duration:26s;animation-delay:-5s">Ω</span>
  <span class="glyph" style="font-size:clamp(3rem,7vw,8rem);left:18%;bottom:18%;animation-duration:32s;animation-delay:-9s">g</span>
  <span class="glyph" style="font-size:clamp(4rem,8vw,9rem);right:22%;bottom:22%;animation-duration:22s;animation-delay:-13s">∑</span>
  <span class="glyph" style="font-size:clamp(3rem,6vw,7rem);left:48%;top:8%;animation-duration:28s;animation-delay:-7s">B</span>

  <!-- animated SVG glyph outline -->
  <svg class="glyph-draw" width="320" height="320" viewBox="0 0 320 320" fill="none">
    <path d="M160 40 C100 40 60 80 60 140 C60 200 100 240 160 240 C220 240 260 200 260 140 C260 80 220 40 160 40 Z M160 80 L160 200 M120 120 L200 120" stroke="white" stroke-width="6" stroke-linecap="round"/>
  </svg>

  <div class="hero-cnt">
    <div class="badge">✦ Professional Font Design</div>
    <h1>Design type.<br><span class="grad">Ship faster.</span></h1>
    <p>Upload, preview, and collaborate on custom typefaces. Export to SVG with named presets. Share with your team.</p>
    <div class="hero-btns">
      <a class="btn-cta" href="/register">
        Start free
        <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
      </a>
      <a class="btn-out" href="#gallery">Browse gallery</a>
    </div>
  </div>

  <div class="scroll-hint"><div class="scroll-arrow"></div></div>
</section>

<!-- STATS -->
<div class="stats-bar">
  <div class="stats-in">
    <div class="stat"><div class="stat-val" id="stat-n">—</div><div class="stat-lbl">Fonts published</div></div>
    <div class="stat"><div class="stat-val">TVF</div><div class="stat-lbl">Native binary format</div></div>
    <div class="stat"><div class="stat-val">3</div><div class="stat-lbl">Export formats</div></div>
    <div class="stat"><div class="stat-val">REST</div><div class="stat-lbl">Full API access</div></div>
  </div>
</div>

<!-- FEATURES -->
<section class="sec" id="features">
  <div class="sec-in">
    <div class="sec-hd fi">
      <div class="sec-lbl">Platform</div>
      <h2 class="sec-ttl">Everything you need to ship type</h2>
      <p class="sec-sub">From glyph editing to export pipelines — TypeVault covers the full font design lifecycle.</p>
    </div>
    <div class="feat-grid">
      <div class="feat-card fi"><div class="feat-icon">◈</div><h3>TVF Format</h3><p>Compact binary font format with glyph path data, rich metadata, and preview callback hooks.</p></div>
      <div class="feat-card fi"><div class="feat-icon">⬡</div><h3>Live SVG Preview</h3><p>Type a string and get an SVG specimen in real-time. Draft preview lets you test before saving.</p></div>
      <div class="feat-card fi"><div class="feat-icon">⊹</div><h3>Team Collaboration</h3><p>Share projects with viewer or editor access. Activity feed keeps everyone in sync on every change.</p></div>
      <div class="feat-card fi"><div class="feat-icon">⊞</div><h3>Export Presets</h3><p>Save named export configs — format, quality, dimensions, watermark — and reuse in one click.</p></div>
      <div class="feat-card fi"><div class="feat-icon">⋮</div><h3>Audit Log</h3><p>Searchable project timeline. Every upload, export, and share event is recorded via the API.</p></div>
      <div class="feat-card fi"><div class="feat-icon">⌬</div><h3>Webhook Callbacks</h3><p>Register a callback URL per font. Triggered automatically on first render for licensing flows.</p></div>
    </div>
  </div>
</section>

<!-- GALLERY -->
<section class="sec gallery-sec" id="gallery">
  <div class="sec-in">
    <div class="sec-hd fi">
      <div class="sec-lbl">Community</div>
      <h2 class="sec-ttl">Latest from the gallery</h2>
      <p class="sec-sub">Explore typefaces published by designers around the world.</p>
    </div>
    <div id="gallery-wrap">
      <div class="gallery-load"><div class="spin"></div>Loading fonts…</div>
    </div>
    <div class="gallery-more fi">
      <a class="btn-out" href="/api/gallery" target="_blank">View full gallery API →</a>
    </div>
  </div>
</section>

<!-- CTA -->
<section class="sec cta-sec fi">
  <div class="sec-in">
    <div class="cta-card">
      <h2>Ready to design your typeface?</h2>
      <p>Join the TypeVault community. Free to start, powerful at scale.</p>
      <a class="btn-cta" style="padding:.9rem 2.4rem;font-size:1rem" href="/register">
        Create free account
        <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
      </a>
    </div>
  </div>
</section>

<!-- FOOTER -->
<footer>
  <div class="foot-in">
    <p>© 2024 TypeVault — Professional font design platform.</p>
    <ul class="foot-links">
    </ul>
  </div>
</footer>

<script>
  // Gallery load
  (async () => {
    const wrap = document.getElementById('gallery-wrap');
    try {
      const r = await fetch('/api/gallery?limit=12&sort_by=downloads&sort_dir=DESC');
      if (!r.ok) throw 0;
      const d = await r.json();
      const list = d.fonts || d.data || [];
      if (!list.length) { wrap.innerHTML = '<p style="text-align:center;color:var(--muted);padding:3rem">No fonts yet.</p>'; return; }

      const grid = document.createElement('div');
      grid.className = 'font-grid';
      const SAMPLE = 'Aa Bb Cc';

      list.forEach((f, i) => {
        const card = document.createElement('div');
        card.className = 'font-card';

        const prev = document.createElement('div');
        prev.className = 'font-prev';
        prev.textContent = SAMPLE;

        const body = document.createElement('div');
        body.className = 'font-body';

        const nm = document.createElement('div');
        nm.className = 'font-name';
        nm.textContent = f.name || 'Untitled';

        const meta = document.createElement('div');
        meta.className = 'font-meta';

        const dl = document.createElement('span');
        dl.textContent = (f.downloads || 0) + ' downloads';
        const lic = document.createElement('span');
        lic.textContent = f.license || 'custom';

        meta.append(dl, lic);
        body.append(nm, meta);
        card.append(prev, body);
        grid.appendChild(card);

        setTimeout(() => card.classList.add('show'), i * 55 + 80);
      });

      wrap.innerHTML = '';
      wrap.appendChild(grid);

      const el = document.getElementById('stat-n');
      if (el) el.textContent = list.length < 12 ? list.length : list.length + '+';
    } catch {
      wrap.innerHTML = '<p style="text-align:center;color:var(--muted);padding:3rem">Could not load gallery.</p>';
    }
  })();

  // Scroll fade-in
  const io = new IntersectionObserver(entries => entries.forEach(e => {
    if (e.isIntersecting) { e.target.classList.add('show'); io.unobserve(e.target); }
  }), { threshold: 0.1 });
  document.querySelectorAll('.fi').forEach(el => io.observe(el));

  // Nav shadow on scroll
  const nav = document.querySelector('nav');
  addEventListener('scroll', () => {
    nav.style.borderBottomColor = scrollY > 50 ? 'rgba(255,255,255,.12)' : 'rgba(255,255,255,.06)';
  });
</script>
</body>
</html>
    """
  end
end
