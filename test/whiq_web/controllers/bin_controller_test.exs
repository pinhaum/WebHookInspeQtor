defmodule WhiqWeb.BinControllerTest do
  use WhiqWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Whiq.Inspector.Bin
  alias Whiq.Repo

  test "BIN-01: POST /bins persists a bin and redirects to its view url", %{conn: conn} do
    conn = post(conn, ~p"/bins")

    assert [bin] = Repo.all(Bin)
    assert redirected_to(conn) == ~p"/bins/#{bin.view_token}"

    {:ok, view, _html} = live(build_conn(), redirected_to(conn))
    assert has_element?(view, "#bin-page")
  end
end
