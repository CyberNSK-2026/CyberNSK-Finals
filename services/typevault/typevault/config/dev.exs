import Config

config :typevault, TypeVault.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "typevault_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :typevault, TypeVaultWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_at_least_64_bytes_long_xxxxxxxxxxxxxxxxxxxxxxxxxxx",
  watchers: []

config :logger, level: :debug
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
