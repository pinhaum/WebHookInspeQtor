defmodule WhiqWeb.CaptureLockRaceTest do
  # A bin deleted after the capture looked it up but before the capture took
  # the bin row lock must be answered 404. The test process holds that lock
  # in its own transaction, so the sandbox runs in :auto mode: the Bandit
  # handler gets its own connection and really blocks on the lock. The bin is
  # deleted on exit in case the test fails before it commits.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Whiq.Inspector
  alias Whiq.Inspector.Bin
  alias Whiq.Inspector.CapturedRequest
  alias Whiq.Repo

  setup do
    :ok = Sandbox.mode(Repo, :auto)
    {:ok, bin} = Inspector.create_bin()

    server = start_supervised!({Bandit, plug: WhiqWeb.Endpoint, ip: :loopback, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :line])

    on_exit(fn ->
      :gen_tcp.close(socket)
      Repo.delete_all(from(b in Bin, where: b.id == ^bin.id))
      Sandbox.mode(Repo, :manual)
    end)

    %{bin: bin, socket: socket}
  end

  # True once another backend waits on a lock held by this connection. Only
  # capture_request/2 locks bin rows, so that backend has already passed the
  # bin lookup.
  defp lock_waiter?() do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM pg_locks WHERE NOT granted AND pg_backend_pid() = ANY(pg_blocking_pids(pid))"
      )

    count > 0
  end

  defp await_lock_waiter(deadline) do
    cond do
      lock_waiter?() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("no capture blocked on the bin lock")

      true ->
        await_lock_waiter(deadline)
    end
  end

  test "a capture into a bin deleted between lookup and lock is answered 404",
       %{bin: bin, socket: socket} do
    {:ok, :committed} =
      Repo.transact(fn ->
        Repo.one!(from(b in Bin, where: b.id == ^bin.id, select: b.id, lock: "FOR UPDATE"))

        :ok =
          :gen_tcp.send(
            socket,
            "POST /h/#{bin.capture_token} HTTP/1.1\r\nhost: localhost\r\n" <>
              "content-type: text/plain\r\ncontent-length: 5\r\n\r\nhello"
          )

        await_lock_waiter(System.monotonic_time(:millisecond) + 5_000)
        {1, _} = Repo.delete_all(from(b in Bin, where: b.id == ^bin.id))
        {:ok, :committed}
      end)

    assert {:ok, "HTTP/1.1 404 Not Found\r\n"} = :gen_tcp.recv(socket, 0, 5_000)
    assert Repo.aggregate(from(r in CapturedRequest, where: r.bin_id == ^bin.id), :count) == 0
  end
end
