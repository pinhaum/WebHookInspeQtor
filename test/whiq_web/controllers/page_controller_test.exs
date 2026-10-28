defmodule WhiqWeb.PageControllerTest do
  use WhiqWeb.ConnCase

  test "GET / renders the create-bin form posting to /bins", %{conn: conn} do
    form =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#create-bin-form")

    assert LazyHTML.attribute(form, "action") == ["/bins"]
    assert LazyHTML.attribute(form, "method") == ["post"]
  end

  test "the header links the whiq brand home and drops the generator links", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("a#site-brand") |> LazyHTML.attribute("href") == ["/"]
    assert document |> LazyHTML.query("#site-brand") |> LazyHTML.text() |> String.trim() == "whiq"
    assert document |> LazyHTML.query(~s(a[href*="phoenixframework.org"])) |> Enum.count() == 0
  end

  test "HEAD / responds 200 with an empty body", %{conn: conn} do
    conn = head(conn, ~p"/")
    assert conn.status == 200
    assert conn.resp_body == ""
  end
end
