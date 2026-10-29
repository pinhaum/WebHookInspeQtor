defmodule WhiqWeb.ClientIPTest do
  # Mutates :whiq application env, so it cannot run alongside other tests.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias WhiqWeb.ClientIP

  setup do
    previous = Application.fetch_env(:whiq, :client_ip_header)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:whiq, :client_ip_header, value)
        :error -> Application.delete_env(:whiq, :client_ip_header)
      end
    end)

    Application.put_env(:whiq, :client_ip_header, "fly-client-ip")
  end

  # A peer address other than Plug.Test's default 127.0.0.1, so a hardcoded fallback fails (L-003).
  defp peer_conn, do: %{conn(:post, "/bins") | remote_ip: {198, 51, 100, 9}}

  test "a configured header with a valid IP wins over the peer address" do
    conn = put_req_header(peer_conn(), "fly-client-ip", "203.0.113.7")

    assert ClientIP.from_conn(conn) == "203.0.113.7"
  end

  test "a configured header with an invalid IP falls back to the peer address" do
    conn = put_req_header(peer_conn(), "fly-client-ip", "not-an-ip")

    assert ClientIP.from_conn(conn) == "198.51.100.9"
  end

  test "a configured header with bytes that are not UTF-8 falls back to the peer address" do
    conn = put_req_header(peer_conn(), "fly-client-ip", <<0xFF, ?1>>)

    assert ClientIP.from_conn(conn) == "198.51.100.9"
  end

  test "a configured header with a valid IP is returned in canonical form" do
    upper = put_req_header(peer_conn(), "fly-client-ip", "2001:DB8:0:0::1")
    lower = put_req_header(peer_conn(), "fly-client-ip", "2001:db8::1")

    assert ClientIP.from_conn(upper) == "2001:db8::1"
    assert ClientIP.from_conn(lower) == "2001:db8::1"
  end

  test "a configured header that is absent falls back to the peer address" do
    assert ClientIP.from_conn(peer_conn()) == "198.51.100.9"
  end

  test "without a configured header the peer address is used even if the header is sent" do
    Application.delete_env(:whiq, :client_ip_header)
    conn = put_req_header(peer_conn(), "fly-client-ip", "203.0.113.7")

    assert ClientIP.from_conn(conn) == "198.51.100.9"
  end
end
