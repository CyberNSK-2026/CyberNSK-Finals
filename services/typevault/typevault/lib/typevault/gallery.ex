defmodule TypeVault.Gallery do
  @moduledoc """
  Query helpers for public gallery pages.
  """

  import Ecto.Query, warn: false
  alias TypeVault.Repo
  alias TypeVault.Fonts.Project

  @default_limit 20
  @max_limit 100

  # Allowlist for plain-column sorts
  @valid_sort_fields ~w(name inserted_at downloads rating)
  @valid_directions  ~w(ASC DESC)

  # Ranking configuration defaults
  @popularity_defaults %{"dw" => "0.4", "rw" => "0.6"}
  @trending_defaults %{"half_life" => "86400"}

  @doc """
  Returns a paginated list of public projects.
  """
  def list_public_fonts(params \\ %{}) do
    direction = resolve_direction(params)
    limit     = params |> Map.get("limit", @default_limit) |> parse_int(@default_limit) |> min(@max_limit)
    offset    = params |> Map.get("offset", 0) |> parse_int(0)

    ranking_config = build_ranking_config(params)
    score_expr     = compile_score_expression(ranking_config)

    {extra_where, where_args} = compose_predicates(
      Map.get(params, "search", ""),
      Map.get(params, "tags", [])
    )

    n = length(where_args)

    # Inner query: applies filtering and ordering; outer query handles pagination
    inner =
      "SELECT fp.id::text, fp.name, fp.description, fp.downloads, fp.rating, fp.tags, fp.license, fp.inserted_at, u.username AS author "
      <> "FROM font_projects fp LEFT JOIN users u ON u.id = fp.user_id "
      <> "WHERE fp.is_public = TRUE#{extra_where} ORDER BY #{score_expr} #{direction}"

    sql = "SELECT * FROM (#{inner}) AS _g LIMIT $#{n + 1} OFFSET $#{n + 2}"

    %{rows: rows, columns: cols} =
      Ecto.Adapters.SQL.query!(Repo, sql, where_args ++ [limit, offset])

    Enum.map(rows, fn row ->
      cols
      |> Enum.zip(row)
      |> Map.new(fn {col, val} -> {String.to_atom(col), val} end)
    end)
  end

  def get_featured_fonts(limit \\ 6) do
    from(p in Project,
      where: p.is_public == true and p.downloads > 0,
      order_by: [desc: p.downloads],
      limit: ^limit,
      select: [:id, :name, :description, :downloads, :rating, :tags]
    )
    |> Repo.all()
  end

  def get_popular_tags do
    from(p in Project,
      where: p.is_public == true,
      select: fragment("unnest(tags)"),
      distinct: true,
      limit: 30
    )
    |> Repo.all()
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  # Accept either `direction` or legacy `sort_dir`; default DESC.
  defp resolve_direction(params) do
    raw = Map.get(params, "direction") || Map.get(params, "sort_dir") || "DESC"
    if raw in @valid_directions, do: raw, else: "DESC"
  end

  # Build ranking configuration from params with defaults
  defp build_ranking_config(params) do
    sort_by = Map.get(params, "sort_by", "rating")

    config = case sort_by do
      "popularity" ->
        Map.merge(@popularity_defaults, params)
        |> Map.take(["dw", "rw"])
        |> Map.put(:profile, "popularity")

      "trending" ->
        Map.merge(@trending_defaults, params)
        |> Map.take(["half_life"])
        |> Map.put(:profile, "trending")

      _ ->
        %{profile: "simple", field: if(sort_by in @valid_sort_fields, do: sort_by, else: "rating")}
    end

    config
  end

  # Compile SQL score expression from ranking configuration
  defp compile_score_expression(%{profile: "popularity"} = config) do
    dw = normalize_weight(Map.get(config, "dw"))
    rw = normalize_weight(Map.get(config, "rw"))
    "fp.downloads * #{dw} + fp.rating * #{rw}"
  end

  defp compile_score_expression(%{profile: "trending"} = config) do
    hl = normalize_weight(Map.get(config, "half_life"))
    "fp.downloads::float / GREATEST(EXTRACT(EPOCH FROM (NOW() - fp.inserted_at)) / #{hl}, 1)"
  end

  defp compile_score_expression(%{profile: "simple", field: field}) do
    "fp.#{field}"
  end

  # Normalize weight value for SQL expression.
  # Accepts numeric input; non-numeric falls back to 1.0.
  # Preserves original string format for downstream formatting.
  defp normalize_weight(value) when is_binary(value) do
    case Float.parse(value) do
      {n, rest} when rest == "" -> Float.to_string(n)
      {_n, _rest} -> value
      :error -> "1.0"
    end
  end

  defp normalize_weight(_), do: "1.0"

  defp compose_predicates(search, tags) do
    {sql, args} =
      if search != "" do
        n = 1
        {" AND (fp.name ILIKE $#{n} OR fp.description ILIKE $#{n})", ["%#{search}%"]}
      else
        {"", []}
      end

    if is_list(tags) and tags != [] do
      n = length(args) + 1
      {"#{sql} AND fp.tags && $#{n}::text[]", args ++ [tags]}
    else
      {sql, args}
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default
end



