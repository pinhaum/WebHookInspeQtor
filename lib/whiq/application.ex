defmodule Whiq.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WhiqWeb.Telemetry,
      Whiq.Repo,
      {Oban, Application.fetch_env!(:whiq, Oban)},
      {DNSCluster, query: Application.get_env(:whiq, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Whiq.PubSub},
      {Whiq.RateLimit, clean_period: :timer.minutes(1)},
      # Start a worker by calling: Whiq.Worker.start_link(arg)
      # {Whiq.Worker, arg},
      # Start to serve requests, typically the last entry
      WhiqWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Whiq.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhiqWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
