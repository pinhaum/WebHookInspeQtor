defmodule WhiqWeb.HealthControllerTest do
  use WhiqWeb.ConnCase, async: true

  test "DEL-13: GET /health answers 200 text/plain ok without a session", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert conn.status == 200
    assert [content_type] = get_resp_header(conn, "content-type")
    assert String.starts_with?(content_type, "text/plain")
    assert conn.resp_body == "ok"
    assert get_resp_header(conn, "set-cookie") == []
  end

  # fetch_session never writes an unused session, so "no set-cookie" alone
  # cannot tell the bare scope from :browser; these outcomes can.
  test "DEL-13: GET /health skips the browser pipeline", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/health")

    assert conn.status == 200
    assert get_resp_header(conn, "x-frame-options") == []
  end

  test "DEL-13: GET /health does not query the database", %{conn: conn} do
    test_pid = self()
    handler_id = {__MODULE__, test_pid}

    :telemetry.attach(
      handler_id,
      [:whiq, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: send(test_pid, :repo_query)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert conn |> get(~p"/health") |> response(200) == "ok"
    refute_received :repo_query
  end
end
