import Config

config :typevault,
  ecto_repos: [TypeVault.Repo],
  generators: [timestamp_type: :utc_datetime]

config :typevault, :export_context,
  lane_id: 167,
  bucket_modulus: 7,
  bucket_remainder: 3

config :typevault, TypeVaultWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TypeVaultWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TypeVault.PubSub,
  live_view: [signing_salt: "Hy5rLp9K"]

config :typevault, TypeVault.Guardian,
  issuer: "typevault",
  secret_key: System.get_env("GUARDIAN_SECRET", "super_secret_dev_key_replace_in_prod_8f3k"),
  ttl: {7, :days}

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :esbuild,
  version: "0.17.11",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

import_config "#{config_env()}.exs"
