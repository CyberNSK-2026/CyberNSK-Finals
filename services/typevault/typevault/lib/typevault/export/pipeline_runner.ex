defmodule TypeVault.Export.PipelineRunner do
  alias TypeVault.TvfParser

  @spec run(binary(), map()) :: binary()
  def run(data, %{"render_pipeline" => stages}) when is_list(stages),
    do: Enum.reduce(stages, data, &run_stage(&2, &1))

  def run(data, %{render_pipeline: stages}) when is_list(stages),
    do: Enum.reduce(stages, data, &run_stage(&2, &1))

  def run(data, _settings), do: data

  defp run_stage(data, %{"stage" => name}) when is_binary(name), do: dispatch(data, name)
  defp run_stage(data, %{stage: name}) when is_binary(name), do: dispatch(data, name)
  defp run_stage(data, _), do: data

  defp dispatch(data, "strip"),     do: safely(fn -> TvfParser.strip_metadata(data) end, data)
  defp dispatch(data, "normalise"), do: safely(fn -> TvfParser.normalise_colour(data) end, data)
  defp dispatch(data, "watermark"), do: safely(fn -> TvfParser.inject_watermark(data) end, data)
  defp dispatch(data, _),           do: data

  defp safely(fun, fallback) do
    try do
      fun.()
    rescue
      _ -> fallback
    end
  end
end
