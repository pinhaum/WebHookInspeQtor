import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :whiq, Whiq.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  database: "whiq_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :whiq, WhiqWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "E6QkhmAmJlOYhezlTaqQogSbrma5zSKa3GaIIz+NdXpyPRL+ZX3VBZ4JfGVOj9Zx",
  server: false

# In test we don't send emails
config :whiq, Whiq.Mailer, adapter: Swoosh.Adapters.Test

# Keeps the capture read-timeout test (CAP-19) fast; prod uses the 15 s default.
config :whiq, :capture_read_timeout, 200

# Small limits so tests can hit them; the window outlasts any test run.
config :whiq, :capture_rate_limit, limit: 2, scale_ms: 3_600_000
config :whiq, :bin_rate_limit, limit: 1, scale_ms: 3_600_000

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
