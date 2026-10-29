defmodule WhiqWeb.BinController do
  use WhiqWeb, :controller

  alias Whiq.Inspector
  alias Whiq.RateLimit
  alias WhiqWeb.ClientIP

  def create(conn, _params) do
    config = Application.fetch_env!(:whiq, :bin_rate_limit)

    case RateLimit.check({:bin, ClientIP.from_conn(conn)}, config[:limit], config[:scale_ms]) do
      :ok ->
        {:ok, bin} = Inspector.create_bin()
        redirect(conn, to: ~p"/bins/#{bin.view_token}")

      {:error, _retry_after} ->
        conn
        |> put_flash(:error, "Too many bins created. Try again later.")
        |> redirect(to: ~p"/")
    end
  end
end
