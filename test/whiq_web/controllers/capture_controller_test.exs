defmodule WhiqWeb.CaptureControllerTest do
  use WhiqWeb.ConnCase, async: true

  import Ecto.Query

  alias Whiq.Inspector
  alias Whiq.Inspector.Bin
  alias Whiq.Inspector.CapturedRequest
  alias Whiq.Repo

  setup do
    {:ok, bin} = Inspector.create_bin()
    %{bin: bin}
  end

  defp stored_request(bin) do
    Repo.one!(from r in CapturedRequest, where: r.bin_id == ^bin.id)
  end

  defp stored_count do
    Repo.aggregate(CapturedRequest, :count)
  end

  test "CAP-01: a request to a live bin is stored once and answered 200 empty",
       %{conn: conn, bin: bin} do
    conn =
      conn
      |> put_req_header("accept", "application/xml")
      |> get("/h/#{bin.capture_token}")

    assert response(conn, 200) == ""
    assert %CapturedRequest{method: "GET"} = stored_request(bin)
  end

  describe "CAP-02: the method is stored as sent" do
    test "HEAD", %{conn: conn, bin: bin} do
      conn = head(conn, "/h/#{bin.capture_token}")

      assert conn.status == 200
      assert stored_request(bin).method == "HEAD"
    end

    test "OPTIONS", %{conn: conn, bin: bin} do
      conn = options(conn, "/h/#{bin.capture_token}")

      assert conn.status == 200
      assert stored_request(bin).method == "OPTIONS"
    end

    test "PROPFIND", %{conn: conn, bin: bin} do
      conn = dispatch(conn, @endpoint, "PROPFIND", "/h/#{bin.capture_token}")

      assert conn.status == 200
      assert stored_request(bin).method == "PROPFIND"
    end

    test "POST with _method=DELETE stays POST", %{conn: conn, bin: bin} do
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/h/#{bin.capture_token}", "_method=DELETE")

      stored = stored_request(bin)
      assert stored.method == "POST"
      assert stored.body == "_method=DELETE"
    end
  end

  test "CAP-03: the subpath after the token is stored", %{conn: conn, bin: bin} do
    post(conn, "/h/#{bin.capture_token}/github/push")

    assert stored_request(bin).path == "/github/push"
  end

  test "CAP-04: no subpath is stored as /", %{conn: conn, bin: bin} do
    post(conn, "/h/#{bin.capture_token}")

    assert stored_request(bin).path == "/"
  end

  test "CAP-05: the query string is stored raw", %{conn: conn, bin: bin} do
    get(conn, "/h/#{bin.capture_token}?b=2&a=%20&a=1")

    assert stored_request(bin).query_string == "b=2&a=%20&a=1"
  end

  test "CAP-06: repeated headers are stored in received order", %{conn: conn, bin: bin} do
    conn = %{conn | req_headers: [{"x-a", "1"}, {"x-b", "2"}, {"x-a", "3"}]}

    post(conn, "/h/#{bin.capture_token}")

    assert stored_request(bin).headers == ["x-a", "1", "x-b", "2", "x-a", "3"]
  end

  test "CAP-07: a random binary body is stored byte-for-byte", %{conn: conn, bin: bin} do
    body = :crypto.strong_rand_bytes(4096)

    conn
    |> put_req_header("content-type", "application/octet-stream")
    |> post("/h/#{bin.capture_token}", body)

    assert stored_request(bin).body == body
  end

  describe "CAP-09: form and JSON bodies are stored as raw bytes" do
    test "multipart/form-data", %{conn: conn, bin: bin} do
      body = "--XyZ\r\ncontent-disposition: form-data; name=\"a\"\r\n\r\n1\r\n--XyZ--\r\n"

      conn
      |> put_req_header("content-type", "multipart/form-data; boundary=XyZ")
      |> post("/h/#{bin.capture_token}", body)

      assert stored_request(bin).body == body
    end

    test "application/x-www-form-urlencoded", %{conn: conn, bin: bin} do
      body = "b=2&a=%20+x"

      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/h/#{bin.capture_token}", body)

      assert stored_request(bin).body == body
    end

    test "application/json", %{conn: conn, bin: bin} do
      body = ~s({"event":"push", "ref":"refs/heads/main"})

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/h/#{bin.capture_token}", body)

      assert stored_request(bin).body == body
    end
  end

  test "CAP-10: a gzip body is stored compressed", %{conn: conn, bin: bin} do
    body = :zlib.gzip(~s({"event":"push"}))

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-encoding", "gzip")
    |> post("/h/#{bin.capture_token}", body)

    assert stored_request(bin).body == body
  end

  test "CAP-11 + CAP-12: body_size and content_type match the request",
       %{conn: conn, bin: bin} do
    conn
    |> put_req_header("content-type", "text/plain; charset=utf-8")
    |> post("/h/#{bin.capture_token}", "olá")

    stored = stored_request(bin)
    assert stored.body_size == 4
    assert stored.content_type == "text/plain; charset=utf-8"
  end

  describe "body size cap" do
    test "LIM-01: a 524,289-byte body is answered 200 and stored truncated to 524,288 bytes",
         %{conn: conn, bin: bin} do
      body = :crypto.strong_rand_bytes(524_289)

      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/h/#{bin.capture_token}", body)

      assert response(conn, 200) == ""
      stored = stored_request(bin)
      assert stored.body == binary_part(body, 0, 524_288)
      assert stored.body_size == 524_288
      assert stored.body_truncated == true
    end

    test "LIM-02: a 524,288-byte body is answered 200 and stored whole",
         %{conn: conn, bin: bin} do
      body = :crypto.strong_rand_bytes(524_288)

      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/h/#{bin.capture_token}", body)

      assert response(conn, 200) == ""
      stored = stored_request(bin)
      assert stored.body == body
      assert stored.body_truncated == false
    end
  end

  # config/test.exs allows 2 captures per bin per hour; each test uses a fresh bin,
  # so counters never leak between tests.
  describe "capture rate limit" do
    defp capture(bin) do
      build_conn()
      |> put_req_header("content-type", "text/plain")
      |> post("/h/#{bin.capture_token}", "x")
    end

    defp stored_ids(bin) do
      Repo.all(
        from r in CapturedRequest, where: r.bin_id == ^bin.id, select: r.id, order_by: r.id
      )
    end

    defp fill!(bin, count) do
      snapshot = %{
        method: "POST",
        path: "/",
        query_string: "",
        headers: [],
        body: "",
        remote_ip: "203.0.113.7"
      }

      for _ <- 1..count, do: {:ok, _} = Inspector.capture_request(bin, snapshot)
    end

    test "LIM-06: captures up to the limit are answered 200", %{bin: bin} do
      assert response(capture(bin), 200) == ""
      assert response(capture(bin), 200) == ""
      assert length(stored_ids(bin)) == 2
    end

    test "LIM-06: the capture over the limit is answered 429 with retry-after and not stored",
         %{bin: bin} do
      capture(bin)
      capture(bin)

      conn = capture(bin)

      assert response(conn, 429) == ""
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert {seconds, ""} = Integer.parse(retry_after)
      assert seconds >= 1
      assert length(stored_ids(bin)) == 2
    end

    test "LIM-12: a rate-limited capture into a full bin evicts nothing", %{bin: bin} do
      fill!(bin, 98)
      capture(bin)
      capture(bin)
      full_ids = stored_ids(bin)
      assert length(full_ids) == 100

      assert capture(bin).status == 429
      assert stored_ids(bin) == full_ids
    end

    test "LIM-08: another bin keeps accepting captures while one is limited", %{bin: bin} do
      {:ok, other} = Inspector.create_bin()
      capture(bin)
      capture(bin)
      assert capture(bin).status == 429

      assert response(capture(other), 200) == ""
      assert length(stored_ids(other)) == 1
    end
  end

  describe "requests that store nothing" do
    test "CAP-16: an unknown capture token is answered 404", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> post("/h/#{String.duplicate("A", 32)}", "x")

      assert response(conn, 404) == ""
      assert stored_count() == 0
    end

    test "CAP-17: an expired bin is answered 404", %{conn: conn, bin: bin} do
      past = DateTime.add(DateTime.utc_now(:second), -1, :second)
      Repo.update_all(from(b in Bin, where: b.id == ^bin.id), set: [expires_at: past])

      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> post("/h/#{bin.capture_token}", "x")

      assert response(conn, 404) == ""
      assert stored_count() == 0
    end

    test "CAP-18: a view token is answered 404", %{conn: conn, bin: bin} do
      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> post("/h/#{bin.view_token}", "x")

      assert response(conn, 404) == ""
      assert stored_count() == 0
    end
  end
end
