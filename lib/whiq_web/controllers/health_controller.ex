defmodule WhiqWeb.HealthController do
  use WhiqWeb, :controller

  # Liveness only: with a single machine, failing on a DB outage would just
  # pull the sole backend out of routing.
  def show(conn, _params) do
    text( conn,"ok" )
  end
end
