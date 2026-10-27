defmodule WhiqWeb.CaptureController do
  use WhiqWeb, :controller

  def capture(conn, _params) do
    send_resp(conn, 200, "")
  end
end
