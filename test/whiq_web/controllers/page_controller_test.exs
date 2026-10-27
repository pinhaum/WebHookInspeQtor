defmodule WhiqWeb.PageControllerTest do
  use WhiqWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "HEAD / responds 200 with an empty body", %{conn: conn} do
    conn = head(conn, ~p"/")
    assert conn.status == 200
    assert conn.resp_body == ""
  end
end
