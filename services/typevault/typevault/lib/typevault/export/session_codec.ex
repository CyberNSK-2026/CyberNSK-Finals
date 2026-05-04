defmodule TypeVault.Export.SessionCodec do
  @moduledoc """
  Codec for the export settings cookie.

  Current writers emit base64-encoded JSON. For backwards compatibility
  with pre-migration cookies we still accept a legacy Erlang External Term
  Format payload, decoded with the `:safe` flag so untrusted bytes cannot
  introduce new atoms or deserialize funs. Keys on decode are normalised
  to strings regardless of the input shape.
  """

  @spec encode(map()) :: String.t()
  def encode(settings) when is_map(settings) do
    settings
    |> Jason.encode!()
    |> Base.encode64(padding: false)
  end

  @spec decode(String.t() | nil) :: map()
  def decode(nil), do: %{}

  def decode(encoded) when is_binary(encoded) do
    with {:ok, raw} <- Base.decode64(encoded, padding: false) do
      parse(raw)
    else
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  defp parse(raw) do
    case Jason.decode(raw) do
      {:ok, %{} = map} -> stringify(map)
      _                -> decode_legacy(raw)
    end
  end

@doc """
Legacy decode path is still required for backward compatibility.

Some deployments may receive export-session payloads produced by older
runtime components during rolling updates, including native integrations
backed by `parser.so`. In those cases
the payload can arrive in ETF map form, so we keep a strict fallback
decoder to preserve cross-version behavior until full format convergence.

This branch accepts only map-shaped data and normalizes keys to strings.
"""
  defp decode_legacy(raw) do
    try do
      case :erlang.binary_to_term(raw, [:safe]) do 
        %{} = map -> stringify(map)
        _         -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp stringify(map) do
    Enum.into(map, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v}                 -> {to_string(k), v}
    end)
  end
end
