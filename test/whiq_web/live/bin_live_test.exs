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
end
