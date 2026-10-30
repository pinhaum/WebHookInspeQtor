defmodule Whiq.Inspector.PruneExpiredBinsTest do
  use Whiq.DataCase, async: false
  use Oban.Testing, repo: Whiq.Repo

  import ExUnit.CaptureLog

  alias Whiq.Inspector
  alias Whiq.Inspector.Bin
  alias Whiq.Inspector.PruneExpiredBins

  # Test config logs warnings only and capture_log cannot go below the global
  # level, so raise it for this sync module (sync tests never overlap).
  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  test "RET-01, RET-03, RET-06: deletes expired bins, keeps live ones and logs the count" do
    {:ok, expired} = Inspector.create_bin()
    {:ok, live} = Inspector.create_bin()
    past = DateTime.add(DateTime.utc_now(:second), -1, :second)
    Repo.update_all(from(b in Bin, where: b.id == ^expired.id), set: [expires_at: past])

    log = capture_log([level: :info], fn -> assert perform_job(PruneExpiredBins, %{}) == :ok end)

    assert Repo.all(from(b in Bin, select: b.id)) == [live.id]
    assert log =~ "[info] Pruned 1 expired bins"
  end

  test "RET-05: completes and deletes nothing when no bin has expired" do
    {:ok, live} = Inspector.create_bin()

    log = capture_log([level: :info], fn -> assert perform_job(PruneExpiredBins, %{}) == :ok end)

    assert Repo.all(from(b in Bin, select: b.id)) == [live.id]
    assert log =~ "[info] Pruned 0 expired bins"
  end
end
