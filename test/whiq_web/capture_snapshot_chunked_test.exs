defmodule WhiqWeb.CaptureSnapshotChunkedTest do
  # Plug.Test and Bandit HTTP/1 fill :length in one read, so the snapshot's
  # multi-read path is driven through an adapter that returns short chunks.
  use ExUnit.Case, async: true

  import Plug.Test

  alias WhiqWeb.CaptureSnapshot
  alias WhiqWeb.ShortReadAdapter

  @token String.duplicate("a", 32)
  @chunk_size 100_000

  defp chunks(body) do
    for <<chunk::binary-size(@chunk_size) <- body>>, do: chunk
  end

  defp snapshot_body(chunks) do
    conn = ShortReadAdapter.conn(conn(:post, "/h/#{@token}"), chunks)
    {snapshot, %Plug.Conn{}} = CaptureSnapshot.from_conn(conn)
    snapshot.body
  end

  test "LIM-02: a body under the cap read in several short chunks is kept whole and in order" do
    body = :crypto.strong_rand_bytes(3 * @chunk_size)

    assert snapshot_body(chunks(body)) == body
  end

  test "LIM-01: a body over the cap read in short chunks is cut at max_body_bytes + 1" do
    limit = Application.fetch_env!(:whiq, :max_body_bytes) + 1
    body = :crypto.strong_rand_bytes(7 * @chunk_size)

    assert snapshot_body(chunks(body)) == binary_part(body, 0, limit)
  end
end
