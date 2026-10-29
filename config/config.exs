# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :whiq,
  ecto_repos: [Whiq.Repo],
  generators: [timestamp_type: :utc_datetime]

# Abuse limits (AD-007): bytes stored per body, requests kept per bin.
config :whiq, :max_body_bytes, 524_288
config :whiq, :max_requests_per_bin, 100
# Fixed-window rate limits: captures per bin, bin creation per client IP.
config :whiq, :capture_rate_limit, limit: 60, scale_ms: 60_000
config :whiq, :bin_rate_limit, limit: 10, scale_ms: 3_600_000

# Background jobs: expired bins are pruned hourly (AD-006); finished job rows
# are kept a week for debugging (RET-07).
config :whiq, Oban,
  repo: Whiq.Repo,
  queues: [default: 5],
  pruner: [max_age: {7, :days}],
  cron: [crontab: [{"@hourly", Whiq.Inspector.PruneExpiredBins}]]

# Configure the endpoint
config :whiq, WhiqWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WhiqWeb.ErrorHTML, json: WhiqWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Whiq.PubSub,
  live_view: [signing_salt: "L9UqShVa"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :whiq, Whiq.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  whiq: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  whiq: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
