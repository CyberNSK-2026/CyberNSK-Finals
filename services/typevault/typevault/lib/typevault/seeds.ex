defmodule TypeVault.Seeds do
  @moduledoc """
  Resets the database and seeds the demo font projects visible in the
  public gallery. Runs on every startup via Release.migrate/0 so no
  state (victim accounts, uploaded fonts, events) survives a restart.
  """

  alias TypeVault.{Repo, Accounts}
  alias TypeVault.Fonts.{Project, FontFile}

  @seed_email "team@typevault.io"

  def run do
    reset_tables()
    user = create_seed_user()
    insert_demo_fonts(user)
    :ok
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp reset_tables do
    {:ok, %{rows: rows}} =
      Ecto.Adapters.SQL.query(
        Repo,
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'",
        []
      )

    tables =
      rows
      |> List.flatten()
      |> Enum.map(&"\"#{&1}\"")
      |> Enum.join(", ")

    if tables != "" do
      Ecto.Adapters.SQL.query!(
        Repo,
        "TRUNCATE TABLE #{tables} RESTART IDENTITY CASCADE",
        []
      )
    end
  end

  defp create_seed_user do
    {:ok, user} =
      Accounts.register_user(%{
        email: @seed_email,
        username: "typevault_team",
        password: :crypto.strong_rand_bytes(32) |> Base.url_encode64()
      })

    user
  end

  defp insert_demo_fonts(user) do
    demos = [
      %{
        name: "Grotesk Display",
        description: "A clean geometric sans-serif designed for display sizes. Inspired by early 20th-century grotesque typefaces.",
        tags: ["sans-serif", "display", "geometric"],
        license: "ofl",
        downloads: 142,
        rating: 4.7,
        filename: "grotesk_display.tvf",
        tvf: build_tvf("Grotesk Display", "Regular", grotesk_glyphs())
      },
      %{
        name: "Serif Nova",
        description: "An elegant serif with moderate contrast and bracketed serifs. Suitable for body text and editorial use.",
        tags: ["serif", "editorial", "body"],
        license: "ofl",
        downloads: 89,
        rating: 4.5,
        filename: "serif_nova.tvf",
        tvf: build_tvf("Serif Nova", "Regular", serif_glyphs())
      },
      %{
        name: "Latin Mono",
        description: "A monospaced typeface with clear letterforms optimised for code and terminal use.",
        tags: ["monospace", "code", "terminal"],
        license: "apache",
        downloads: 217,
        rating: 4.8,
        filename: "latin_mono.tvf",
        tvf: build_tvf("Latin Mono", "Regular", mono_glyphs())
      }
    ]

    Enum.each(demos, fn demo ->
      {:ok, project} =
        %Project{}
        |> Project.changeset(%{
             name: demo.name,
             description: demo.description,
             tags: demo.tags,
             license: demo.license,
             is_public: true
           })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Ecto.Changeset.put_change(:downloads, demo.downloads)
        |> Ecto.Changeset.put_change(:rating, demo.rating)
        |> Repo.insert()

      {:ok, _} =
        %FontFile{}
        |> FontFile.changeset(%{
             filename: demo.filename,
             data: demo.tvf,
             file_size: byte_size(demo.tvf)
           })
        |> Ecto.Changeset.put_change(:project_id, project.id)
        |> Repo.insert()
    end)
  end

  # ── TVF binary builder ──────────────────────────────────────────────────────

  defp build_tvf(name, style, glyphs) do
    meta = [{"font_name", name}, {"style", style}, {"version", "1.0"}]
    meta_bin = Enum.reduce(meta, <<>>, fn {k, v}, acc ->
      acc <> <<byte_size(k)::8>> <> k <> <<0x01, byte_size(v)::little-16>> <> v
    end)

    glyph_bin = Enum.reduce(glyphs, <<>>, fn {char_code, _advance, cmds}, acc ->
      real_cmds = Enum.reject(cmds, &(&1 == :close))
      path_bin  = Enum.reduce(real_cmds, <<>>, fn cmd, pb -> pb <> encode_cmd(cmd) end)
      acc <> <<char_code::little-16, length(real_cmds)::little-16>> <> path_bin
    end)

    header = <<"TVF1",
               1::little-16,
               length(meta)::little-16,
               length(glyphs)::little-16,
               0::little-16>>

    header <> meta_bin <> glyph_bin
  end

  defp encode_cmd({:move, x, y}),  do: <<0, x::little-signed-16, y::little-signed-16>>
  defp encode_cmd({:line, x, y}),  do: <<1, x::little-signed-16, y::little-signed-16>>
  defp encode_cmd({:curve, cx1, cy1, cx2, cy2, x, y}) do
    cx = div(cx1 + cx2, 2)
    cy = div(cy1 + cy2, 2)
    <<2, x::little-signed-16, y::little-signed-16, cx::little-signed-16, cy::little-signed-16>>
  end
  defp encode_cmd(:close), do: <<>>

  # ── Glyph data ──────────────────────────────────────────────────────────────
  # Each glyph: {char_code, advance_width, [path_commands]}

  defp grotesk_glyphs do
    [
      {?A, 580, [{:move, 290, 700}, {:line, 0, 0}, {:line, 580, 0}, :close,
                 {:move, 72, 175}, {:line, 508, 175}, :close]},
      {?B, 560, [{:move, 0, 0}, {:line, 0, 700}, {:line, 360, 700},
                 {:curve, 480, 700, 530, 640, 530, 560},
                 {:curve, 530, 490, 490, 430, 380, 400},
                 {:curve, 500, 380, 560, 320, 560, 230},
                 {:curve, 560, 120, 490, 0, 340, 0},
                 :close]},
      {?H, 620, [{:move, 0, 0}, {:line, 0, 700}, :close,
                 {:move, 620, 0}, {:line, 620, 700}, :close,
                 {:move, 0, 350}, {:line, 620, 350}, :close]},
      {?O, 640, [{:move, 320, 0},
                 {:curve, 160, 0, 50, 100, 50, 350},
                 {:curve, 50, 600, 160, 700, 320, 700},
                 {:curve, 480, 700, 590, 600, 590, 350},
                 {:curve, 590, 100, 480, 0, 320, 0},
                 :close]},
      {?T, 520, [{:move, 260, 0}, {:line, 260, 700}, :close,
                 {:move, 0, 700}, {:line, 520, 700}, :close]},
      {?e, 540, [{:move, 50, 280}, {:line, 490, 280},
                 {:curve, 490, 100, 390, 0, 270, 0},
                 {:curve, 120, 0, 50, 120, 50, 270},
                 {:curve, 50, 430, 140, 530, 290, 530},
                 {:curve, 410, 530, 490, 460, 490, 380},
                 :close]}
    ]
  end

  defp serif_glyphs do
    [
      {?A, 600, [{:move, 300, 700}, {:line, 20, 0}, {:line, 80, 0}, :close,
                 {:move, 300, 700}, {:line, 580, 0}, {:line, 520, 0}, :close,
                 {:move, 100, 220}, {:line, 500, 220}, :close,
                 {:move, 20, 0},  {:line, 0, 0},   {:line, 0, 40},   :close,
                 {:move, 580, 0}, {:line, 600, 0}, {:line, 600, 40}, :close]},
      {?I, 240, [{:move, 120, 0}, {:line, 120, 700}, :close,
                 {:move, 60, 0},  {:line, 180, 0},   :close,
                 {:move, 60, 700},{:line, 180, 700},  :close]},
      {?n, 520, [{:move, 0, 0}, {:line, 0, 500}, :close,
                 {:move, 0, 420},
                 {:curve, 0, 500, 80, 530, 180, 530},
                 {:curve, 300, 530, 360, 460, 360, 350},
                 {:line, 360, 0}, :close,
                 {:move, 0, 0},   {:line, -20, 0}, {:line, -20, 40}, :close,
                 {:move, 360, 0}, {:line, 380, 0}, {:line, 380, 40}, :close]},
      {?s, 480, [{:move, 430, 420},
                 {:curve, 430, 540, 350, 530, 240, 530},
                 {:curve, 120, 530, 60, 480, 60, 390},
                 {:curve, 60, 300, 150, 270, 300, 250},
                 {:curve, 420, 230, 480, 190, 480, 100},
                 {:curve, 480, 0, 390, -10, 240, -10},
                 {:curve, 120, -10, 40, 30, 40, 80},
                 :close]}
    ]
  end

  defp mono_glyphs do
    letters = Enum.to_list(?A..?Z) ++ Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9)
    Enum.map(letters, fn ch ->
      {ch, 600, simple_box_glyph(ch)}
    end)
  end

  # Generate simple rectangular strokes for monospace font
  defp simple_box_glyph(ch) when ch in ?A..?Z do
    [
      {:move, 60, 0}, {:line, 60, 700},
      :close,
      {:move, 540, 0}, {:line, 540, 700},
      :close,
      {:move, 60, 700}, {:line, 540, 700},
      :close,
      {:move, 60, 350}, {:line, rem(ch - ?A, 3) * 60 + 240, 350},
      :close
    ]
  end

  defp simple_box_glyph(ch) when ch in ?a..?z do
    offset = ch - ?a
    base_y = rem(offset, 4) * 40
    [
      {:move, 80, base_y}, {:line, 80, 500 + base_y},
      :close,
      {:move, 80, 500 + base_y},
      {:curve, 80, 530 + base_y, 200, 540 + base_y, 300, 530 + base_y},
      {:curve, 440, 510 + base_y, 520, 420 + base_y, 520, 280 + base_y},
      {:curve, 520, 100 + base_y, 400, base_y, 240, base_y},
      {:curve, 140, base_y, 80, 40 + base_y, 80, 80 + base_y},
      :close
    ]
  end

  defp simple_box_glyph(ch) when ch in ?0..?9 do
    d = ch - ?0
    w = 500
    h = 700
    [
      {:move, div(w, 2), 0},
      {:curve, 80, 0, 60, 120, 60, div(h, 2)},
      {:curve, 60, h - 120, 80, h, div(w, 2), h},
      {:curve, w - 80, h, w - 60, h - 120, w - 60, div(h, 2)},
      {:curve, w - 60, 120, w - 80, 0, div(w, 2), 0},
      :close,
      {:move, div(w, 2) - 30, div(h, 2) - 30},
      {:line, div(w, 2) - 30 + rem(d * 17, 60), div(h, 2) + 30},
      :close
    ]
  end

end
