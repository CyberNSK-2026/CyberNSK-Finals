defmodule TypeVaultWeb.GalleryController do
  use TypeVaultWeb, :controller

  alias TypeVault.Gallery

  action_fallback TypeVaultWeb.FallbackController

  @doc """
  GET /api/gallery

  Query params:
    search    - search term
    sort_by   - field to sort by: name | rating | downloads | inserted_at
    sort_dir  - sort direction: ASC | DESC
    limit     - max results (default 20, max 100)
    offset    - pagination offset
    tags[]    - filter by tags
  """
  def index(conn, params) do
    fonts = Gallery.list_public_fonts(params)
    json(conn, %{fonts: fonts, count: length(fonts)})
  end

  def featured(conn, _params) do
    fonts = Gallery.get_featured_fonts(6)
    json(conn, %{fonts: fonts})
  end

  def tags(conn, _params) do
    tags = Gallery.get_popular_tags()
    json(conn, %{tags: tags})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, project} <- TypeVault.Fonts.get_accessible_project(id, nil) do
      json(conn, %{font: project_public_json(project)})
    end
  end

  defp project_public_json(p) do
    %{
      id: p.id,
      name: p.name,
      description: p.description,
      downloads: p.downloads,
      rating: p.rating,
      tags: p.tags,
      license: p.license,
      inserted_at: p.inserted_at
    }
  end
end
