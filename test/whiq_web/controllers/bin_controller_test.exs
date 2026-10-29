defmodule WhiqWeb.BinControllerTest do
  use WhiqWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Whiq.Inspector.Bin
  alias Whiq.Repo

  # config/test.exs allows 1 bin per IP per hour and the counters are shared
  # across async tests, so every test posts from its own address.
  defp unique_ip do
    n = System.unique_integer([:positive])
    {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}
  end

  defp create_bin(ip), do: post(%{build_conn() | remote_ip: ip}, ~p"/bins")

  test "BIN-01: POST /bins persists a bin and redirects to its view url" do
    conn = create_bin(unique_ip())

    assert [bin] = Repo.all(Bin)
    assert redirected_to(conn) == ~p"/bins/#{bin.view_token}"

    {:ok, view, _html} = live(build_conn(), redirected_to(conn))
    assert has_element?(view, "#bin-page")
  end

  describe "bin creation rate limit" do
    test "LIM-09: the creation over the limit makes no bin and shows the message on /" do
      ip = unique_ip()
      first = create_bin(ip)
      assert [bin] = Repo.all(Bin)
      assert redirected_to(first) == ~p"/bins/#{bin.view_token}"

      second = create_bin(ip)

      assert redirected_to(second) == ~p"/"
      assert Repo.aggregate(Bin, :count) == 1

      flash =
        second
        |> recycle()
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#flash-error")

      assert LazyHTML.text(flash) =~ "Too many bins created. Try again later."
    end

    test "LIM-10: another IP still creates a bin while one is limited" do
      limited = unique_ip()
      create_bin(limited)
      assert redirected_to(create_bin(limited)) == ~p"/"

      conn = create_bin(unique_ip())

      assert Repo.aggregate(Bin, :count) == 2
      assert redirected_to(conn) =~ ~r"\A/bins/[A-Za-z0-9_-]{32}\z"
    end
  end
end
