defmodule TypeVaultWeb.ToolsController do
  use TypeVaultWeb, :controller

  @max_name_len 64

  def generate_form(conn, _params) do
    html(conn, render_page(nil, nil))
  end

  def generate_tvf(conn, params) do
    name  = String.slice(params["font_name"]  || "My Font", 0, @max_name_len)
    style = String.slice(params["font_style"] || "Regular", 0, 32)
    style = if style in ~w(Regular Bold Italic BoldItalic Light Medium), do: style, else: "Regular"

    glyph_set = params["glyph_set"] || "basic"

    glyphs = build_glyphs(glyph_set)
    data   = build_tvf(name, style, glyphs)
    slug   = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")

    conn
    |> put_resp_content_type("application/octet-stream")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{slug}.tvf"))
    |> send_resp(200, data)
  end

  # ── TVF builder ─────────────────────────────────────────────────────────────

  defp build_tvf(name, style, glyphs) do
    # Metadata keys must match what the Rust parser and renderer expect
    meta = [{"font_name", name}, {"style", style}, {"version", "1.0"}]
    # Format: [u8: key_len][key_bytes][0x01][u16 LE: val_len][val_bytes]
    meta_bin = Enum.reduce(meta, <<>>, fn {k, v}, acc ->
      key_bytes = :binary.bin_to_list(k) |> :binary.list_to_bin()
      val_bytes = :binary.bin_to_list(v) |> :binary.list_to_bin()
      acc <> <<byte_size(key_bytes)::8>> <> key_bytes <>
             <<0x01, byte_size(val_bytes)::little-16>> <> val_bytes
    end)

    glyph_bin = Enum.reduce(glyphs, <<>>, fn {char_code, _advance, cmds}, acc ->
      # Filter out :close — Rust parser has no close opcode; MoveTo starts new contour
      real_cmds = Enum.reject(cmds, &(&1 == :close))
      path_bin  = Enum.reduce(real_cmds, <<>>, fn cmd, pb -> pb <> encode_cmd(cmd) end)
      # Glyph header: [u16: codepoint][u16: num_cmds] — no advance field
      acc <> <<char_code::little-16, length(real_cmds)::little-16>> <> path_bin
    end)

    # Header: "TVF1" + version + meta_count + glyph_count + reserved
    <<"TVF1",
      1::little-16,
      length(meta)::little-16,
      length(glyphs)::little-16,
      0::little-16>> <> meta_bin <> glyph_bin
  end

  # Opcodes: 0=MoveTo, 1=LineTo, 2=CurveTo — matches Rust parser
  # CurveTo format: [u8:2][i16:x][i16:y][i16:cx][i16:cy] (endpoint first, then control point)
  defp encode_cmd({:move, x, y}),  do: <<0, x::little-signed-16, y::little-signed-16>>
  defp encode_cmd({:line, x, y}),  do: <<1, x::little-signed-16, y::little-signed-16>>
  defp encode_cmd({:curve, cx1, cy1, cx2, cy2, x, y}) do
    # Cubic → quadratic: average the two control points
    cx = div(cx1 + cx2, 2)
    cy = div(cy1 + cy2, 2)
    <<2, x::little-signed-16, y::little-signed-16, cx::little-signed-16, cy::little-signed-16>>
  end
  defp encode_cmd(:close), do: <<>>

  # ── Glyph sets ──────────────────────────────────────────────────────────────

  defp build_glyphs("basic") do
    for ch <- Enum.to_list(?A..?Z) ++ Enum.to_list(?a..?z) do
      {ch, 600, letter_cmds(ch)}
    end
  end

  defp build_glyphs("alphanumeric") do
    for ch <- Enum.to_list(?A..?Z) ++ Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9) do
      {ch, 600, letter_cmds(ch)}
    end
  end

  defp build_glyphs("full") do
    printable = Enum.to_list(?!) ++ Enum.to_list(?A..?Z) ++
                Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9) ++
                [?., ?,, ?!, ??, ?-, ?_]
    for ch <- printable do
      {ch, 600, letter_cmds(ch)}
    end
  end

  defp build_glyphs(_), do: build_glyphs("basic")

  defp letter_cmds(ch) when ch in ?A..?Z do
    t = ch - ?A
    [
      {:move, 60, 0}, {:line, 60 + rem(t, 3) * 30, 700},
      :close,
      {:move, 540, 0}, {:line, 540 - rem(t, 4) * 20, 700},
      :close,
      {:move, 60, 700}, {:line, 540, 700}, :close,
      {:move, 60 + t * 4, 300}, {:line, 540 - t * 3, 300}, :close
    ]
  end

  defp letter_cmds(ch) when ch in ?a..?z do
    t = ch - ?a
    mid = 200 + rem(t * 13, 120)
    [
      {:move, 100, 0}, {:line, 100, 500}, :close,
      {:move, 100, 500 - rem(t, 5) * 20},
      {:curve, 100, 530, 200 + t * 2, 540, 300, 530},
      {:curve, 420 + rem(t, 3) * 10, 510, 500, 400 + rem(t, 4) * 15, 500, mid},
      {:curve, 500, 80 + rem(t, 3) * 10, 400, 0, 250, 0},
      {:curve, 150, 0, 100, 50 + rem(t, 4) * 10, 100, 80 + rem(t, 5) * 8},
      :close
    ]
  end

  defp letter_cmds(ch) when ch in ?0..?9 do
    d = ch - ?0
    [
      {:move, 300, 0},
      {:curve, 100, 0, 80, 100, 80, 350},
      {:curve, 80, 600, 100, 700, 300, 700},
      {:curve, 500, 700, 520, 600, 520, 350},
      {:curve, 520, 100, 500, 0, 300, 0},
      :close,
      {:move, 300 - d * 5, 320}, {:line, 300 + d * 5, 380}, :close
    ]
  end

  defp letter_cmds(_ch) do
    [{:move, 100, 0}, {:line, 500, 0}, {:line, 500, 700}, {:line, 100, 700}, :close]
  end

  # ── HTML page ───────────────────────────────────────────────────────────────

  defp render_page(_error, _result) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8"/>
      <title>TVF Generator — TypeVault</title>
      <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{background:#09090f;color:#e2e8f0;font-family:system-ui,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:2rem}
        .card{background:#13131f;border:1px solid rgba(255,255,255,.08);border-radius:18px;padding:2.5rem;width:100%;max-width:480px}
        h1{font-size:1.4rem;font-weight:800;letter-spacing:-.03em;margin-bottom:.4rem}
        .sub{color:#64748b;font-size:.875rem;margin-bottom:2rem}
        label{display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500}
        input,select{width:100%;padding:.7rem 1rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;margin-bottom:1.1rem}
        input:focus,select:focus{border-color:#7c3aed}
        select option{background:#09090f}
        button{width:100%;padding:.85rem;background:#7c3aed;border:none;border-radius:9px;color:#fff;font-size:.95rem;font-weight:700;cursor:pointer;letter-spacing:-.01em;margin-top:.5rem}
        button:hover{background:#6d28d9}
        .back{display:inline-block;color:#64748b;font-size:.8rem;text-decoration:none;margin-top:1.5rem}
        .back:hover{color:#a78bfa}
        .badge{display:inline-block;background:rgba(124,58,237,.15);color:#a78bfa;border:1px solid rgba(124,58,237,.3);border-radius:6px;font-size:.72rem;font-weight:600;padding:.2rem .55rem;margin-bottom:1.5rem}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="badge">TVF Generator</div>
        <h1>Generate .tvf font file</h1>
        <p class="sub">Create a TypeVault Font binary for testing and exploration.</p>

        <form method="post" action="/tools/generate">
          <input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}"/>

          <label>Font name</label>
          <input type="text" name="font_name" value="My Typeface" placeholder="e.g. Grotesk Display" maxlength="64" required/>

          <label>Style</label>
          <select name="font_style">
            <option value="Regular">Regular</option>
            <option value="Bold">Bold</option>
            <option value="Italic">Italic</option>
            <option value="Light">Light</option>
            <option value="Medium">Medium</option>
          </select>

          <label>Glyph set</label>
          <select name="glyph_set">
            <option value="basic">Basic A–Z a–z (52 glyphs)</option>
            <option value="alphanumeric">Alphanumeric A–Z a–z 0–9 (62 glyphs)</option>
            <option value="full">Full printable ASCII (96 glyphs)</option>
          </select>

          <button type="submit">⬇ Download .tvf</button>
        </form>

        <a href="/gallery" class="back">← Back to Gallery</a>
      </div>
    </body>
    </html>
    """
  end
end
