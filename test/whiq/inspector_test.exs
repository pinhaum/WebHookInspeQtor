defmodule Whiq.InspectorTest do
  use Whiq.DataCase, async: true

  alias Whiq.Inspector
  alias Whiq.Inspector.Bin

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
end
