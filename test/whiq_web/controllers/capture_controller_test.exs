defmodule WhiqWeb.CaptureControllerTest do
  use WhiqWeb.ConnCase, async: true

  defp assert_captured(conn) do
    assert conn.private.phoenix_controller == WhiqWeb.CaptureController
    conn
  end

  test "a request with a body reaches the controller unparsed and fully readable", %{conn: conn} do
    body = ~s({"event":"push","ref":"refs/heads/main"})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/h/tok123", body)
      |> assert_captured()

    assert %Plug.Conn.Unfetched{aspect: :body_params} = conn.body_params
    assert {:ok, ^body, _conn} = Plug.Conn.read_body(conn)
  end

  test "HEAD keeps its method", %{conn: conn} do
    conn = conn |> head("/h/tok123") |> assert_captured()

    assert conn.method == "HEAD"
  end

  test "POST with _method=DELETE keeps its method", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/h/tok123", "_method=DELETE")
      |> assert_captured()

    assert conn.method == "POST"
  end

  test "a sub-path under the token reaches the controller", %{conn: conn} do
    conn = conn |> get("/h/tok123/any/sub/path") |> assert_captured()

    assert conn.status == 200
  end

  test "a non-standard method reaches the controller", %{conn: conn} do
    conn = conn |> dispatch(@endpoint, "PROPFIND", "/h/tok123") |> assert_captured()

    assert conn.method == "PROPFIND"
  end

  test "an XML Accept header is answered with 200", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/xml")
      |> get("/h/tok123")
      |> assert_captured()

    assert conn.status == 200
  end
end
