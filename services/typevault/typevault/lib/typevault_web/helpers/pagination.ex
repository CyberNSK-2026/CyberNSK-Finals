defmodule TypeVaultWeb.Helpers.Pagination do
  @moduledoc """
  Unified API response envelope with pagination metadata.

  All paginated list endpoints should use `paginate/3` to wrap their results
  in a consistent `{data, meta}` structure.
  """

  @doc """
  Wraps a list of items with pagination metadata.

      iex> Pagination.paginate(items, 100, %{limit: 20, offset: 0})
      %{data: [...], meta: %{total: 100, limit: 20, offset: 0, has_more: true}}
  """
  def paginate(items, total, %{limit: limit, offset: offset}) do
    %{
      data: items,
      meta: %{
        total: total,
        limit: limit,
        offset: offset,
        has_more: offset + length(items) < total
      }
    }
  end

  @doc """
  Parses `:limit` and `:offset` from request params.

  Applies sensible defaults and caps the limit at `max_limit`.
  """
  def parse_pagination(params, default_limit \\ 20, max_limit \\ 100) do
    limit =
      params
      |> Map.get("limit", default_limit)
      |> parse_int(default_limit)
      |> min(max_limit)
      |> max(1)

    offset =
      params
      |> Map.get("offset", 0)
      |> parse_int(0)
      |> max(0)

    %{limit: limit, offset: offset}
  end

  defp parse_int(v, _default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default
end
