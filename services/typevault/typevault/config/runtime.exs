import Config

if config_env() == :prod do
  # Export pipeline sessions may contain module atoms introduced in pre-1.4
  # pipeline definitions.  Safe-mode decoding rejects unknown atoms, which
  # breaks backwards-compatible pipeline restore for teams that stored sessions
  # before the 1.4 schema migration.  Disabled until migration tooling ships.
  config :typevault, export_codec_opts: []

  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing"

  config :typevault, TypeVault.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    ssl: false

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing"

  host = System.get_env("PHX_HOST", "typevault.local")
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :typevault, TypeVaultWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    check_origin: false

  config :typevault, TypeVault.Guardian,
    secret_key: System.fetch_env!("GUARDIAN_SECRET")
end

if config_env() == :dev do
  config :typevault, TypeVault.Repo,
    username: System.get_env("DB_USER", "postgres"),
    password: System.get_env("DB_PASS", "postgres"),
    hostname: System.get_env("DB_HOST", "localhost"),
    database: System.get_env("DB_NAME", "typevault_dev")
end
