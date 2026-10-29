defmodule Whiq.InspectorConcurrencyTest do
  # The SQL sandbox funnels every process through one connection, which would
  # serialize the captures and hide a missing bin lock. This module runs with
  # the sandbox in :auto mode instead, so each capture holds a real connection
  # and commits; the bin (and, by cascade, its requests) is deleted on exit.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Whiq.Inspector
  alias Whiq.Inspector.Bin
  alias Whiq.Inspector.CapturedRequest
  alias Whiq.Repo

  @parallel 20

  setup do
    :ok = Sandbox.mode(Repo, :auto)
    {:ok, bin} = Inspector.create_bin()

    on_exit(fn ->
      Repo.delete_all(from(b in Bin, where: b.id == ^bin.id))
      Sandbox.mode(Repo, :manual)
    end)

    %{bin: bin}
  end

  defp snapshot do
    %{
      method: "POST",
      path: "/concurrent",
      query_string: "",
      headers: [],
      body: "x",
      remote_ip: "203.0.113.7"
    }
  end

  defp stored_ids(bin) do
    CapturedRequest
    |> where([r], r.bin_id == ^bin.id)
    |> select([r], r.id)
    |> Repo.all()
    |> Enum.sort()
  end

  # Each task pins its own connection, reports the backend pid, and waits for
  # the go signal, so all captures start while every connection is held.
  defp capture_in_parallel(bin, count) do
    test_pid = self()

    tasks =
      for _ <- 1..count do
        Task.async(fn ->
          Repo.checkout(fn ->
            %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
            send(test_pid, {:ready, self()})

            receive do
              :go -> :ok
            end

            {:ok, %CapturedRequest{id: id}} = Inspector.capture_request(bin, snapshot())
            {backend_pid, id}
          end)
        end)
      end

    ready =
      for _ <- tasks do
        assert_receive {:ready, pid}, 5_000
        pid
      end

    Enum.each(ready, &send(&1, :go))

    Task.await_many(tasks, 15_000)
  end

  test "LIM-04: 20 concurrent captures into a bin holding 95 requests keep exactly the 100 newest",
       %{bin: bin} do
    seeded_ids =
      for _ <- 1..95 do
        {:ok, %CapturedRequest{id: id}} = Inspector.capture_request(bin, snapshot())
        id
      end

    results = capture_in_parallel(bin, @parallel)
    {backend_pids, new_ids} = Enum.unzip(results)

    assert backend_pids |> Enum.uniq() |> length() == @parallel

    newest_seeded = Enum.drop(seeded_ids, 95 + @parallel - 100)
    assert stored_ids(bin) == Enum.sort(newest_seeded ++ new_ids)
  end
end
