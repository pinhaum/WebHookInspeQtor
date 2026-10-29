defmodule WhiqWeb.CaptureController do
  use WhiqWeb, :controller

  alias Whiq.Inspector
  alias Whiq.RateLimit
  alias WhiqWeb.CaptureSnapshot

  # The bin is looked up and rate-limited before the body is read, so unknown
  # tokens and denied captures cost no memory and store nothing.
  def capture(conn, %{"token" => token}) do
    with {:ok, bin} <- Inspector.fetch_live_bin_by_capture_token(token),
         :ok <- check_rate(bin) do
      {snapshot, conn} = CaptureSnapshot.from_conn(conn)

      case Inspector.capture_request(bin, snapshot) do
        {:ok, _request} -> send_resp(conn, 200, "")
        {:error, :not_found} -> send_resp(conn, 404, "")
      end
    else
      {:error, :not_found} ->
        send_resp(conn, 404, "")

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> send_resp(429, "")
    end
  end

  defp check_rate(bin) do
    config = Application.fetch_env!(:whiq, :capture_rate_limit)
    RateLimit.check({:capture, bin.id}, config[:limit], config[:scale_ms])
  end
end
