defmodule TypeVault.TvfParser do
  @moduledoc """
  Rustler NIF wrapper for the TVF (TypeVault Font) binary format parser.

  The TVF format is a compact binary font format supporting:
  - Glyph path data (M/L/C bezier commands)
  - Rich metadata (name, author, license, etc.)
  - Optional external glyph library references
  """

  use Rustler, otp_app: :typevault, crate: "tvf_parser", skip_compilation?: true

  @doc """
  Parses a TVF binary font file. Returns parsed metadata and glyph info.

  Returns:
    {:ok, %{metadata: map(), glyph_count: integer(), format_version: integer()}}
    {:error, reason :: atom()}
  """
  def parse_font(_binary), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Validates and normalizes a preview callback URL in the Rust layer.

  Returns {:ok, url} or {:error, reason}.
  """
  def validate_callback_url(_url), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Renders text with a parsed TVF font as SVG markup.

  Returns {:ok, svg_binary} or {:error, reason}
  """
  def render_text(_font_data, _text, _size), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Generates a basic font specimen sheet as SVG.
  Shows all available glyphs at various sizes.
  """
  def render_specimen(_font_data, _sample_text), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Runs the raw opcode-stream FSM.

  `raw_bytes`     – validated raw TVF opcode stream (binary, NOT a full TVF file).
  `context_label` – arbitrary label embedded into the output SVG when the
                    decoder's sink condition fires (used for project watermarks).

  Returns {:ok, svg_string}.
  """
  def render_preview(_raw_bytes, _context_label), do: :erlang.nif_error(:nif_not_loaded)
end
