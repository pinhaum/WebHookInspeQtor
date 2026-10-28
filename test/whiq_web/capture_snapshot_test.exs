defmodule WhiqWeb.CaptureSnapshotTest do
  # Mutates :whiq application env, so it cannot run alongside other tests.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias WhiqWeb.CaptureSnapshot

  @token String.duplicate("a", 32)

  setup do
    previous = Application.fetch_env(:whiq, :client_ip_header)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:whiq, :client_ip_header, value)
        :error -> Application.delete_env(:whiq, :client_ip_header)
      end
    end)

    Application.delete_env(:whiq, :client_ip_header)
  end

  defp snapshot(conn) do
    {snapshot, %Plug.Conn{}} = CaptureSnapshot.from_conn(conn)
    snapshot
  end

  test "CAP-02: a non-standard method is kept as sent" do
    assert snapshot(conn("PROPFIND", "/h/#{@token}")).method == "PROPFIND"
  end

  test "CAP-03: the path after the token is kept, still percent-encoded" do
    assert snapshot(conn(:post, "/h/#{@token}/github/push")).path == "/github/push"
    assert snapshot(conn(:post, "/h/#{@token}/a%20b")).path == "/a%20b"
  end

  test "CAP-04: no subpath is recorded as /" do
    assert snapshot(conn(:post, "/h/#{@token}")).path == "/"
  end

  test "CAP-05: the query string is kept raw" do
    assert snapshot(conn(:get, "/h/#{@token}?b=2&a=%20")).query_string == "b=2&a=%20"
  end

  test "CAP-06: repeated headers keep their order" do
    conn = %{
      conn(:post, "/h/#{@token}")
      | req_headers: [{"x-a", "1"}, {"x-b", "2"}, {"x-a", "3"}]
    }

    assert snapshot(conn).headers == [{"x-a", "1"}, {"x-b", "2"}, {"x-a", "3"}]
  end

  test "CAP-07: a body larger than one read_body chunk is returned complete" do
    body = :binary.copy("x", 8_000_001)

    assert snapshot(conn(:post, "/h/#{@token}", body)).body == body
  end

  test "CAP-13: a configured header with a valid IP is the remote_ip" do
    Application.put_env(:whiq, :client_ip_header, "fly-client-ip")

    conn = conn(:post, "/h/#{@token}") |> put_req_header("fly-client-ip", "203.0.113.7")

    assert snapshot(conn).remote_ip == "203.0.113.7"
  end

  test "CAP-14: without a configured header the peer address is the remote_ip" do
    conn = conn(:post, "/h/#{@token}") |> put_req_header("fly-client-ip", "203.0.113.7")

    assert snapshot(conn).remote_ip == "127.0.0.1"
  end

  test "CAP-20: a configured header that is absent falls back to the peer address" do
    Application.put_env(:whiq, :client_ip_header, "fly-client-ip")

    assert snapshot(conn(:post, "/h/#{@token}")).remote_ip == "127.0.0.1"
  end

  test "CAP-20: a configured header that is not an IP falls back to the peer address" do
    Application.put_env(:whiq, :client_ip_header, "fly-client-ip")

    conn = conn(:post, "/h/#{@token}") |> put_req_header("fly-client-ip", "not-an-ip")

    assert snapshot(conn).remote_ip == "127.0.0.1"
  end

  test "CAP-21: a request without a body has an empty body" do
    assert snapshot(conn(:get, "/h/#{@token}")).body == ""
  end
end
