defmodule WhiqWeb.CaptureSnapshot do
  @moduledoc """
  The only place that turns a `Plug.Conn` under `/h/` into the plain map
  `Whiq.Inspector.capture_request/2` stores (AD-004). Nothing is parsed,
  decoded or reordered.
  """

  alias WhiqWeb.ClientIP

  @default_read_timeout 15_000

  @doc """
  Drains the request body and returns the snapshot with the updated conn.
  """
  def from_conn(%Plug.Conn{} = conn) do
    {body, conn} = read_full_body(conn, [])

    snapshot = %{
      method: conn.method,
      path: capture_path(conn.request_path),
      query_string: conn.query_string,
      headers: conn.req_headers,
      body: body,
      remote_ip: ClientIP.from_conn(conn)
    }

    {snapshot, conn}
  end

  defp read_full_body(conn, acc) do
    read_timeout = Application.get_env(:whiq, :capture_read_timeout, @default_read_timeout)

    case Plug.Conn.read_body(conn, read_timeout: read_timeout) do
      {:ok, chunk, conn} -> {IO.iodata_to_binary([acc, chunk]), conn}
      {:more, chunk, conn} -> read_full_body(conn, [acc, chunk])
    end
  end

  # request_path is what was sent; path_params["path"] would be percent-decoded.
  defp capture_path("/h/" <> token_and_path) do
    case String.split(token_and_path, "/", parts: 2) do
      [_token] -> "/"
      [_token, path] -> "/" <> path
    end
  end
end
