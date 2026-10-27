defmodule Whiq.Repo do
  use Ecto.Repo,
    otp_app: :whiq,
    adapter: Ecto.Adapters.Postgres
end
