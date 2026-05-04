defmodule TypeVault.Release do
  @moduledoc "Used for executing DB release tasks when run in production without Mix."

  @app :typevault

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn r ->
          Ecto.Migrator.run(r, :up, all: true)
          TypeVault.Seeds.run()
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
