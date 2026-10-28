defmodule Whiq.InspectorTest do
  use Whiq.DataCase, async: true

  alias Whiq.Inspector
  alias Whiq.Inspector.Bin
  alias Whiq.Inspector.CapturedRequest

  @token_format ~r/\A[A-Za-z0-9_-]{32}\z/

  describe "create_bin/0" do
    test "BIN-02: persists two distinct 32-char url-safe tokens, unique across bins" do
      {:ok, %Bin{id: id}} = Inspector.create_bin()
      {:ok, %Bin{id: other_id}} = Inspector.create_bin()

      bin = Repo.get!(Bin, id)
      other = Repo.get!(Bin, other_id)

      assert bin.capture_token =~ @token_format
      assert bin.view_token =~ @token_format
      assert bin.capture_token != bin.view_token

      tokens = [bin.capture_token, bin.view_token, other.capture_token, other.view_token]
      assert tokens |> Enum.uniq() |> length() == 4
    end

    test "BIN-03: persists expires_at exactly 7 days after inserted_at" do
      {:ok, %Bin{id: id}} = Inspector.create_bin()

      bin = Repo.get!(Bin, id)

      assert DateTime.diff(bin.expires_at, bin.inserted_at) == 7 * 86_400
    end
  end

  describe "fetch_live_bin_by_view_token/1" do
    test "returns the live bin for its view token" do
      {:ok, %Bin{id: id, view_token: view_token}} = Inspector.create_bin()

      assert {:ok, %Bin{id: ^id}} = Inspector.fetch_live_bin_by_view_token(view_token)
    end

    test "BIN-08: a well-formed token that matches no bin is not found" do
      {:ok, _bin} = Inspector.create_bin()

      assert Inspector.fetch_live_bin_by_view_token(String.duplicate("A", 32)) ==
               {:error, :not_found}
    end

    test "BIN-09: the bin's capture token is not found" do
      {:ok, bin} = Inspector.create_bin()

      assert Inspector.fetch_live_bin_by_view_token(bin.capture_token) == {:error, :not_found}
    end

    test "BIN-10: a bin past its expires_at is not found" do
      {:ok, bin} = Inspector.create_bin()
      past = DateTime.add(DateTime.utc_now(:second), -1, :second)
      Repo.update_all(from(b in Bin, where: b.id == ^bin.id), set: [expires_at: past])

      assert Inspector.fetch_live_bin_by_view_token(bin.view_token) == {:error, :not_found}
    end

    test "BIN-12: a malformed token is not found without querying the database" do
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

      valid_prefix = String.duplicate("a", 31)

      malformed = [
        valid_prefix <> ".",
        valid_prefix <> "/",
        valid_prefix <> "+",
        valid_prefix <> "=",
        valid_prefix,
        valid_prefix <> "aa"
      ]

      for token <- malformed do
        assert Inspector.fetch_live_bin_by_view_token(token) == {:error, :not_found}
      end

      refute_received :repo_query
    end
  end

  describe "fetch_live_bin_by_capture_token/1" do
    test "returns the live bin for its capture token" do
      {:ok, %Bin{id: id, capture_token: capture_token}} = Inspector.create_bin()

      assert {:ok, %Bin{id: ^id}} = Inspector.fetch_live_bin_by_capture_token(capture_token)
    end

    test "CAP-16: a well-formed token that matches no bin is not found" do
      {:ok, _bin} = Inspector.create_bin()

      assert Inspector.fetch_live_bin_by_capture_token(String.duplicate("A", 32)) ==
               {:error, :not_found}
    end

    test "CAP-16: a malformed token is not found without querying the database" do
      test_pid = self()
      handler_id = {__MODULE__, :capture, test_pid}

      :telemetry.attach(
        handler_id,
        [:whiq, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if self() == test_pid, do: send(test_pid, :repo_query)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      valid_prefix = String.duplicate("a", 31)

      for token <- [valid_prefix <> ".", valid_prefix, valid_prefix <> "aa"] do
        assert Inspector.fetch_live_bin_by_capture_token(token) == {:error, :not_found}
      end

      refute_received :repo_query
    end

    test "CAP-17: a bin past its expires_at is not found" do
      {:ok, bin} = Inspector.create_bin()
      past = DateTime.add(DateTime.utc_now(:second), -1, :second)
      Repo.update_all(from(b in Bin, where: b.id == ^bin.id), set: [expires_at: past])

      assert Inspector.fetch_live_bin_by_capture_token(bin.capture_token) == {:error, :not_found}
    end

    test "CAP-18: the bin's view token is not found" do
      {:ok, bin} = Inspector.create_bin()

      assert Inspector.fetch_live_bin_by_capture_token(bin.view_token) == {:error, :not_found}
    end
  end

  describe "capture_request/2" do
    defp snapshot(overrides \\ %{}) do
      Map.merge(
        %{
          method: "POST",
          path: "/github/push",
          query_string: "b=2&a=%20",
          headers: [{"content-type", "application/json"}, {"x-a", "1"}],
          body: ~s({"ok":true}),
          remote_ip: "203.0.113.7"
        },
        overrides
      )
    end

    defp capture!(bin, snapshot) do
      {:ok, %CapturedRequest{id: id}} = Inspector.capture_request(bin, snapshot)
      Repo.get!(CapturedRequest, id)
    end

    test "stores every snapshot field as given for the bin" do
      {:ok, bin} = Inspector.create_bin()

      stored = capture!(bin, snapshot())

      assert stored.bin_id == bin.id
      assert stored.method == "POST"
      assert stored.path == "/github/push"
      assert stored.query_string == "b=2&a=%20"
      assert stored.headers == ["content-type", "application/json", "x-a", "1"]
      assert stored.body == ~s({"ok":true})
      assert stored.remote_ip == "203.0.113.7"
      assert %DateTime{microsecond: {_, 6}} = stored.inserted_at
    end

    test "CAP-06: repeated headers are stored as flat pairs in received order" do
      {:ok, bin} = Inspector.create_bin()
      headers = [{"x-a", "1"}, {"x-b", "2"}, {"x-a", "3"}]

      stored = capture!(bin, snapshot(%{headers: headers}))

      assert stored.headers == ["x-a", "1", "x-b", "2", "x-a", "3"]
    end

    test "CAP-06: a header value with non-UTF-8 bytes round-trips" do
      {:ok, bin} = Inspector.create_bin()
      value = <<0xFF, 0x80>>

      stored = capture!(bin, snapshot(%{headers: [{"x-raw", value}]}))

      assert stored.headers == ["x-raw", value]
    end

    test "CAP-07: a random binary body round-trips byte-for-byte" do
      {:ok, bin} = Inspector.create_bin()
      body = :crypto.strong_rand_bytes(1024)

      stored = capture!(bin, snapshot(%{body: body}))

      assert stored.body == body
    end

    test "CAP-11: body_size is the byte size of the body" do
      {:ok, bin} = Inspector.create_bin()

      stored = capture!(bin, snapshot(%{body: "é"}))

      assert stored.body_size == 2
    end

    test "CAP-12: content_type comes from the content-type header, nil without it" do
      {:ok, bin} = Inspector.create_bin()

      with_header = capture!(bin, snapshot(%{headers: [{"content-type", "text/plain; a=b"}]}))
      without_header = capture!(bin, snapshot(%{headers: [{"x-a", "1"}]}))

      assert with_header.content_type == "text/plain; a=b"
      assert without_header.content_type == nil
    end

    test "CAP-15: a Plug.Conn is rejected and nothing is stored" do
      {:ok, bin} = Inspector.create_bin()

      assert_raise FunctionClauseError, fn ->
        Inspector.capture_request(bin, Plug.Test.conn(:post, "/h/token", "body"))
      end

      assert Repo.aggregate(CapturedRequest, :count) == 0
    end

    test "CAP-21: an empty body is stored as an empty binary with body_size 0" do
      {:ok, bin} = Inspector.create_bin()

      stored = capture!(bin, snapshot(%{body: ""}))

      assert stored.body == ""
      assert stored.body_size == 0
    end
  end

  # The local PubSub adapter delivers during broadcast, so the message is
  # already in the mailbox when capture_request/2 returns.
  describe "subscribe/1" do
    test "LIVE-02: a subscriber of the bin receives the stored request" do
      {:ok, bin} = Inspector.create_bin()
      :ok = Inspector.subscribe(bin)

      {:ok, %CapturedRequest{id: id}} = Inspector.capture_request(bin, snapshot())

      assert_received {:request_captured, request}
      assert request == Repo.get!(CapturedRequest, id)
    end

    test "LIVE-03: a subscriber of one bin receives nothing for another bin's capture" do
      {:ok, bin} = Inspector.create_bin()
      {:ok, other} = Inspector.create_bin()
      :ok = Inspector.subscribe(bin)

      {:ok, _request} = Inspector.capture_request(other, snapshot())

      refute_received {:request_captured, _}
    end
  end

  describe "list_requests/1" do
    test "LIVE-01: lists only the bin's requests, newest first" do
      {:ok, bin} = Inspector.create_bin()
      {:ok, other} = Inspector.create_bin()
      older = capture!(bin, snapshot(%{path: "/older"}))
      newer = capture!(bin, snapshot(%{path: "/newer"}))
      _foreign = capture!(other, snapshot())

      assert Enum.map(Inspector.list_requests(bin), & &1.id) == [newer.id, older.id]
    end

    test "LIVE-01: requests with the same timestamp are ordered by id, newest first" do
      {:ok, bin} = Inspector.create_bin()
      first = capture!(bin, snapshot())
      second = capture!(bin, snapshot())

      Repo.update_all(from(r in CapturedRequest, where: r.bin_id == ^bin.id),
        set: [inserted_at: first.inserted_at]
      )

      assert Enum.map(Inspector.list_requests(bin), & &1.id) == [second.id, first.id]
    end

    test "LIVE-01: loads method, path, body size and timestamp but not body or headers" do
      {:ok, bin} = Inspector.create_bin()
      stored = capture!(bin, snapshot())

      assert [listed] = Inspector.list_requests(bin)
      assert listed.id == stored.id
      assert listed.method == "POST"
      assert listed.path == "/github/push"
      assert listed.body_size == byte_size(~s({"ok":true}))
      assert listed.inserted_at == stored.inserted_at
      assert listed.body == nil
      assert listed.headers == nil
    end
  end

  describe "fetch_request/2" do
    test "LIVE-06: returns the full request when it belongs to the bin" do
      {:ok, bin} = Inspector.create_bin()
      stored = capture!(bin, snapshot())

      assert Inspector.fetch_request(bin, stored.id) == {:ok, stored}
    end

    test "LIVE-06: another bin's request is not found" do
      {:ok, bin} = Inspector.create_bin()
      {:ok, other} = Inspector.create_bin()
      foreign = capture!(other, snapshot())

      assert Inspector.fetch_request(bin, foreign.id) == {:error, :not_found}
    end
  end
end
