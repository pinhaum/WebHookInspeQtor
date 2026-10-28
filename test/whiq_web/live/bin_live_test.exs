defmodule WhiqWeb.BinLiveTest do
  use WhiqWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Whiq.Inspector
  alias Whiq.Inspector.Bin
  alias Whiq.Repo

  setup do
    {:ok, bin} = Inspector.create_bin()
    %{bin: bin}
  end

  defp capture!(bin, overrides \\ %{}) do
    snapshot =
      Map.merge(
        %{
          method: "POST",
          path: "/hook",
          query_string: "",
          headers: [{"content-type", "application/json"}],
          body: ~s({"ok":true}),
          remote_ip: "203.0.113.7"
        },
        overrides
      )

    {:ok, request} = Inspector.capture_request(bin, snapshot)
    request
  end

  defp text(document, selector) do
    document |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
  end

  defp row_ids(document) do
    document |> LazyHTML.query("#requests > li") |> LazyHTML.attribute("id")
  end

  describe "access" do
    test "the bin's view token mounts the bin page", %{conn: conn, bin: bin} do
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")

      assert has_element?(view, "#bin-page")
    end

    test "BIN-08: an unknown token responds 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/bins/#{String.duplicate("A", 32)}") end
    end

    test "BIN-09: the bin's capture token responds 404", %{conn: conn, bin: bin} do
      assert_error_sent 404, fn -> get(conn, ~p"/bins/#{bin.capture_token}") end
    end

    test "BIN-10: an expired bin responds 404", %{conn: conn, bin: bin} do
      past = DateTime.add(DateTime.utc_now(:second), -1, :second)
      Repo.update_all(from(b in Bin, where: b.id == ^bin.id), set: [expires_at: past])

      assert_error_sent 404, fn -> get(conn, ~p"/bins/#{bin.view_token}") end
    end

    test "BIN-12: a malformed token responds 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/bins/#{String.duplicate("a", 31) <> "."}") end
    end
  end

  describe "bin page" do
    setup %{conn: conn, bin: bin} do
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      %{view: view, document: view |> render() |> LazyHTML.from_fragment()}
    end

    test "BIN-04: shows the absolute capture url", %{document: document, bin: bin} do
      capture_url = WhiqWeb.Endpoint.url() <> "/h/" <> bin.capture_token

      assert document |> LazyHTML.query("#capture-url") |> LazyHTML.attribute("value") ==
               [capture_url]
    end

    test "BIN-05: shows the expiry as an ISO 8601 UTC timestamp", %{document: document, bin: bin} do
      assert document |> LazyHTML.query("#expires-at") |> LazyHTML.text() |> String.trim() ==
               DateTime.to_iso8601(bin.expires_at)
    end

    test "BIN-06: shows the save-url notice", %{document: document} do
      assert document |> LazyHTML.query("#save-url-notice") |> LazyHTML.text() |> String.trim() ==
               "Save this page's URL: it is the only way back to this bin."
    end

    # Deliberate raw-HTML check: BIN-11 is about a string being absent (design.md Risks).
    test "BIN-11: never renders the view token", %{conn: conn, view: view, bin: bin} do
      dead_html = conn |> get(~p"/bins/#{bin.view_token}") |> html_response(200)

      refute dead_html =~ bin.view_token
      refute render(view) =~ bin.view_token
    end

    test "BIN-07: Copy dispatches whiq:copy to the capture url input", %{document: document} do
      [phx_click] =
        document |> LazyHTML.query("#copy-capture-url") |> LazyHTML.attribute("phx-click")

      assert Jason.decode!(phx_click) == [
               ["dispatch", %{"event" => "whiq:copy", "to" => "#capture-url"}]
             ]
    end
  end
  describe "request list" do
    test "LIVE-01: lists captured requests newest first with method, path, timestamp and size",
         %{conn: conn, bin: bin} do
      older = capture!(bin, %{method: "PUT", path: "/older", body: "abc"})
      newer = capture!(bin, %{method: "DELETE", path: "/newer", body: ""})

      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      document = view |> render() |> LazyHTML.from_fragment()

      assert row_ids(document) == ["requests-#{newer.id}", "requests-#{older.id}"]

      assert text(document, "#requests-#{newer.id}-method") == "DELETE"
      assert text(document, "#requests-#{newer.id}-path") == "/newer"
      assert text(document, "#requests-#{newer.id}-time") == DateTime.to_iso8601(newer.inserted_at)
      assert text(document, "#requests-#{newer.id}-size") == "0 bytes"

      assert text(document, "#requests-#{older.id}-method") == "PUT"
      assert text(document, "#requests-#{older.id}-path") == "/older"
      assert text(document, "#requests-#{older.id}-time") == DateTime.to_iso8601(older.inserted_at)
      assert text(document, "#requests-#{older.id}-size") == "3 bytes"
    end

    test "LIVE-05: an empty bin shows a curl command targeting the capture url",
         %{conn: conn, bin: bin} do
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      document = view |> render() |> LazyHTML.from_fragment()

      capture_url = WhiqWeb.Endpoint.url() <> "/h/" <> bin.capture_token
      assert text(document, "#empty-state-curl") == "curl -d 'hello' #{capture_url}"
      assert row_ids(document) == []
    end

    test "LIVE-05: the empty state is not shown once the bin has a request",
         %{conn: conn, bin: bin} do
      capture!(bin)

      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")

      refute has_element?(view, "#empty-state")
    end
  end
end
