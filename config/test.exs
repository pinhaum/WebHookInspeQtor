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
  # LIM-04 holds 20 connections at once (test/whiq/inspector_concurrency_test.exs).
  pool_size: max(System.schedulers_online() * 2, 24)

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

# Small limits so tests can hit them; a one-year window cannot close mid-test,
# so counted hits never straddle a wall-clock window boundary.
config :whiq, :capture_rate_limit, limit: 2, scale_ms: :timer.hours(24 * 365)
config :whiq, :bin_rate_limit, limit: 1, scale_ms: :timer.hours(24 * 365)

# Jobs run only when a test performs them (Oban.Testing).
config :whiq, Oban, testing: :manual

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
