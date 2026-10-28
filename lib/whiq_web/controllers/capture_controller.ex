defmodule WhiqWeb.CaptureController do
  use WhiqWeb, :controller

  alias Whiq.Inspector
  alias WhiqWeb.CaptureSnapshot

  # The bin is looked up before the body is read, so unknown tokens cost no memory.
  def capture(conn, %{"token" => token}) do
    case Inspector.fetch_live_bin_by_capture_token(token) do
      {:ok, bin} ->
        {snapshot, conn} = CaptureSnapshot.from_conn(conn)

        case Inspector.capture_request(bin, snapshot) do
          {:ok, _request} -> send_resp(conn, 200, "")
          {:error, :not_found} -> send_resp(conn, 404, "")
        end

      {:error, :not_found} ->
        send_resp(conn, 404, "")
    end
  end
end
