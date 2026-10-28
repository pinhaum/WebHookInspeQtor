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

      assert text(document, "#requests-#{newer.id}-time") ==
               DateTime.to_iso8601(newer.inserted_at)

      assert text(document, "#requests-#{newer.id}-size") == "0 bytes"

      assert text(document, "#requests-#{older.id}-method") == "PUT"
      assert text(document, "#requests-#{older.id}-path") == "/older"

      assert text(document, "#requests-#{older.id}-time") ==
               DateTime.to_iso8601(older.inserted_at)

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

  # Inspector broadcasts synchronously, so the LiveView has the message in its
  # mailbox before render/1 asks it for the current HTML.
  describe "live updates" do
    test "LIVE-02: a new capture appears first on every open page of the bin",
         %{conn: conn, bin: bin} do
      older = capture!(bin)
      {:ok, view_a, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      {:ok, view_b, _html} = live(conn, ~p"/bins/#{bin.view_token}")

      newer = capture!(bin, %{path: "/live"})

      for view <- [view_a, view_b] do
        document = view |> render() |> LazyHTML.from_fragment()
        assert row_ids(document) == ["requests-#{newer.id}", "requests-#{older.id}"]
        assert text(document, "#requests-#{newer.id}-path") == "/live"
      end
    end

    test "LIVE-03: a capture into another bin leaves the page unchanged",
         %{conn: conn, bin: bin} do
      {:ok, other} = Inspector.create_bin()
      capture!(bin)
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      before = render(view)

      capture!(other)

      assert render(view) == before
    end

    test "LIVE-05: the empty state disappears on the first live arrival",
         %{conn: conn, bin: bin} do
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      assert has_element?(view, "#empty-state")

      request = capture!(bin)

      refute has_element?(view, "#empty-state")
      assert has_element?(view, "#requests-#{request.id}")
    end
  end

  describe "request detail" do
    defp detail(conn, bin) do
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      {view, view |> render() |> LazyHTML.from_fragment()}
    end

    defp header_pairs(document) do
      document
      |> LazyHTML.query("#request-headers > li")
      |> Enum.map(fn header ->
        {text(header, "[id$='-name']"), text(header, "[id$='-value']")}
      end)
    end

    defp body(document) do
      body = LazyHTML.query(document, "#request-body")
      {LazyHTML.attribute(body, "data-format"), LazyHTML.text(body)}
    end

    test "LIVE-12: the newest request is detailed on load", %{conn: conn, bin: bin} do
      capture!(bin, %{path: "/older"})
      newer = capture!(bin, %{path: "/newer"})

      {_view, document} = detail(conn, bin)

      assert text(document, "#detail-path") == "/newer"
      assert text(document, "#detail-time") == DateTime.to_iso8601(newer.inserted_at)
    end

    test "LIVE-06: shows every field and every header pair in stored order",
         %{conn: conn, bin: bin} do
      request =
        capture!(bin, %{
          method: "PATCH",
          path: "/github/push",
          query_string: "b=2&a=%20",
          headers: [
            {"content-type", "text/plain; charset=utf-8"},
            {"x-a", "1"},
            {"x-b", "2"},
            {"x-a", "3"}
          ],
          body: "hello",
          remote_ip: "198.51.100.4"
        })

      {_view, document} = detail(conn, bin)

      assert text(document, "#detail-method") == "PATCH"
      assert text(document, "#detail-path") == "/github/push"
      assert text(document, "#detail-query") == "b=2&a=%20"
      assert text(document, "#detail-content-type") == "text/plain; charset=utf-8"
      assert text(document, "#detail-remote-ip") == "198.51.100.4"
      assert text(document, "#detail-time") == DateTime.to_iso8601(request.inserted_at)
      assert text(document, "#detail-size") == "5 bytes"

      assert header_pairs(document) == [
               {"content-type", "text/plain; charset=utf-8"},
               {"x-a", "1"},
               {"x-b", "2"},
               {"x-a", "3"}
             ]
    end

    test "LIVE-07: a valid UTF-8 body is shown as text", %{conn: conn, bin: bin} do
      capture!(bin, %{body: "olá\nmundo"})

      {_view, document} = detail(conn, bin)

      assert body(document) == {["text"], "olá\nmundo"}
    end

    test "LIVE-08: a non-UTF-8 body is shown as a hex dump", %{conn: conn, bin: bin} do
      capture!(bin, %{body: <<0xFF, 0x00, 0x41>>})

      {_view, document} = detail(conn, bin)

      assert body(document) == {["hex"], "00000000  ff 00 41"}
    end

    test "LIVE-15: invalid UTF-8 after the first byte hex-dumps the whole body",
         %{conn: conn, bin: bin} do
      capture!(bin, %{body: "ok" <> <<0xFF>>})

      {_view, document} = detail(conn, bin)

      assert body(document) == {["hex"], "00000000  6f 6b ff"}
    end

    test "LIVE-09: an empty body shows (empty body)", %{conn: conn, bin: bin} do
      capture!(bin, %{body: ""})

      {_view, document} = detail(conn, bin)

      assert {["empty"], text} = body(document)
      assert String.trim(text) == "(empty body)"
    end

    test "LIVE-11: captured markup renders as escaped text, never as elements",
         %{conn: conn, bin: bin} do
      script = "<script>alert(1)</script>"

      capture!(bin, %{
        query_string: "q=" <> script,
        headers: [{"x-evil", script}, {"x-" <> script, "1"}],
        body: script
      })

      {_view, document} = detail(conn, bin)

      assert document |> LazyHTML.query("#request-detail script") |> Enum.count() == 0
      assert text(document, "#detail-query") == "q=" <> script
      assert header_pairs(document) == [{"x-evil", script}, {"x-" <> script, "1"}]
      assert body(document) == {["text"], script}
    end

    test "LIVE-11/AD-008: non-UTF-8 header values and content type render escaped",
         %{conn: conn, bin: bin} do
      capture!(bin, %{
        headers: [{"content-type", "text/plain" <> <<0xFF>>}, {"x-raw", <<0xFF, 0x80>>}],
        body: <<0xFF>>
      })

      {view, document} = detail(conn, bin)

      assert text(document, "#detail-content-type") == "text/plain\\xff"

      assert header_pairs(document) == [
               {"content-type", "text/plain\\xff"},
               {"x-raw", "\\xff\\x80"}
             ]

      assert body(document) == {["hex"], "00000000  ff"}
      assert render(view) |> String.valid?()
    end
  end

  describe "selection" do
    defp selected_rows(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#requests button[aria-current='true']")
      |> LazyHTML.attribute("id")
    end

    defp detail_path(view) do
      view |> render() |> LazyHTML.from_fragment() |> text("#detail-path")
    end

    test "LIVE-06: each row is a select control carrying its request id",
         %{conn: conn, bin: bin} do
      request = capture!(bin)

      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")

      assert has_element?(
               view,
               "button#requests-#{request.id}-select[type='button'][phx-click='select'][phx-value-id='#{request.id}']"
             )
    end

    test "LIVE-06: clicking an older row shows its detail and marks it selected",
         %{conn: conn, bin: bin} do
      older = capture!(bin, %{path: "/older"})
      newer = capture!(bin, %{path: "/newer"})
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      assert selected_rows(view) == ["requests-#{newer.id}-select"]

      view |> element("#requests-#{older.id}-select") |> render_click()

      assert detail_path(view) == "/older"
      assert selected_rows(view) == ["requests-#{older.id}-select"]
    end

    test "LIVE-13: a live arrival keeps the current selection", %{conn: conn, bin: bin} do
      older = capture!(bin, %{path: "/older"})
      capture!(bin, %{path: "/newer"})
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      view |> element("#requests-#{older.id}-select") |> render_click()

      capture!(bin, %{path: "/latest"})

      assert detail_path(view) == "/older"
      assert selected_rows(view) == ["requests-#{older.id}-select"]
    end

    test "LIVE-13: a live arrival into an empty bin becomes the selection",
         %{conn: conn, bin: bin} do
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      refute has_element?(view, "#request-detail")

      request = capture!(bin, %{path: "/first"})

      assert detail_path(view) == "/first"
      assert selected_rows(view) == ["requests-#{request.id}-select"]
    end

    test "a forged select with a foreign or malformed id leaves the page unchanged",
         %{conn: conn, bin: bin} do
      {:ok, other} = Inspector.create_bin()
      foreign = capture!(other, %{path: "/foreign"})
      older = capture!(bin, %{path: "/older"})
      capture!(bin, %{path: "/newer"})
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      before = render(view)

      for id <- ["#{foreign.id}", "abc", "#{older.id}x", "", older.id] do
        render_hook(view, "select", %{"id" => id})
        assert render(view) == before
      end
    end
  end

  describe "eviction" do
    defp fill!(bin, count) do
      for n <- 1..count, do: capture!(bin, %{path: "/fill-#{n}"})
    end

    defp rendered_row_ids(view), do: view |> render() |> LazyHTML.from_fragment() |> row_ids()

    defp detail_path_of(view) do
      view |> render() |> LazyHTML.from_fragment() |> text("#detail-path")
    end

    defp selected_row_ids(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#requests button[aria-current='true']")
      |> LazyHTML.attribute("id")
    end

    test "LIVE-04: an evicted request disappears from every open page",
         %{conn: conn, bin: bin} do
      [oldest | _] = fill!(bin, 100)
      {:ok, first, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      {:ok, second, _html} = live(build_conn(), ~p"/bins/#{bin.view_token}")

      latest = capture!(bin, %{path: "/latest"})

      for view <- [first, second] do
        ids = rendered_row_ids(view)
        refute has_element?(view, "#requests-#{oldest.id}")
        assert length(ids) == 100
        assert hd(ids) == "requests-#{latest.id}"
      end
    end

    test "LIVE-14: when the selected request is evicted the newest remaining is selected",
         %{conn: conn, bin: bin} do
      [oldest | _] = fill!(bin, 100)
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      view |> element("#requests-#{oldest.id}-select") |> render_click()
      assert detail_path_of(view) == "/fill-1"

      latest = capture!(bin, %{path: "/latest"})

      assert has_element?(view, "#request-detail")
      assert detail_path_of(view) == "/latest"
      assert selected_row_ids(view) == ["requests-#{latest.id}-select"]
    end

    test "an eviction of an unselected request keeps the current selection",
         %{conn: conn, bin: bin} do
      [_oldest, second_oldest | _] = fill!(bin, 100)
      {:ok, view, _html} = live(conn, ~p"/bins/#{bin.view_token}")
      view |> element("#requests-#{second_oldest.id}-select") |> render_click()

      capture!(bin, %{path: "/latest"})

      assert detail_path_of(view) == "/fill-2"
      assert selected_row_ids(view) == ["requests-#{second_oldest.id}-select"]
    end
  end
end
