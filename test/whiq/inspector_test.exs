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
end
