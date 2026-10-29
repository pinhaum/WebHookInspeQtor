defmodule WhiqWeb.CaptureSnapshot do
  @moduledoc """
  The only place that turns a `Plug.Conn` under `/h/` into the plain map
  `Whiq.Inspector.capture_request/2` stores (AD-004). Nothing is parsed,
  decoded or reordered.
  """

  alias WhiqWeb.ClientIP

  @default_read_timeout 15_000

  @doc """
  Reads the request body up to one byte past the `:max_body_bytes` config
  and returns the snapshot with the updated conn. The remainder is left
  unread; the extra byte lets `Whiq.Inspector` tell a body at the cap from
  one over it (LIM-01, LIM-02).
  """
  def from_conn(%Plug.Conn{} = conn) do
    limit = Application.fetch_env!(:whiq, :max_body_bytes) + 1
    {body, conn} = read_bounded_body(conn, [], 0, limit)

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

  defp read_bounded_body(conn, acc, size, limit) do
    read_timeout = Application.get_env(:whiq, :capture_read_timeout, @default_read_timeout)

    case Plug.Conn.read_body(conn, length: limit - size, read_timeout: read_timeout) do
      {:ok, chunk, conn} ->
        {cap([acc, chunk], limit), conn}

      {:more, chunk, conn} when size + byte_size(chunk) >= limit ->
        {cap([acc, chunk], limit), conn}

      {:more, chunk, conn} ->
        read_bounded_body(conn, [acc, chunk], size + byte_size(chunk), limit)
    end
  end

  # An adapter may return more than :length asks for.
  defp cap(iodata, limit) do
    body = IO.iodata_to_binary(iodata)
    binary_part(body, 0, min(byte_size(body), limit))
  end

  # request_path is what was sent; path_params["path"] would be percent-decoded.
  defp capture_path("/h/" <> token_and_path) do
    case String.split(token_and_path, "/", parts: 2) do
      [_token] -> "/"
      [_token, path] -> "/" <> path
    end
  end
end
