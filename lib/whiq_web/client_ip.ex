defmodule WhiqWeb.ClientIP do
  @moduledoc """
  The client IP of a request as a canonical string: the value of the
  configured `:client_ip_header` (`fly-client-ip` in prod) when it holds a
  valid IP, otherwise the peer address.
  """

  def from_conn(%Plug.Conn{} = conn) do
    with header when is_binary(header) <- Application.get_env(:whiq, :client_ip_header),
         [value | _] <- Plug.Conn.get_req_header(conn, header),
         {:ok, ip} <- :inet.parse_strict_address(:binary.bin_to_list(value)) do
      format(ip)
    else
      _ -> format(conn.remote_ip)
    end
  end

  defp format(ip), do: ip |> :inet.ntoa() |> to_string()
end
