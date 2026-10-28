defmodule WhiqWeb.ClientIP do
  @moduledoc """
  The client IP of a request as a string: the value of the configured
  `:client_ip_header` (`fly-client-ip` in prod) when it holds a valid IP,
  otherwise the peer address.
  """

  def from_conn(%Plug.Conn{} = conn) do
    with header when is_binary(header) <- Application.get_env(:whiq, :client_ip_header),
         [value | _] <- Plug.Conn.get_req_header(conn, header),
         {:ok, _ip} <- :inet.parse_strict_address(String.to_charlist(value)) do
      value
    else
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
