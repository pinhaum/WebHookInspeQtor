defmodule Whiq.ObanConfigTest do
  use ExUnit.Case, async: true

  # Test config sets `testing: :manual`, which strips plugins; drop it to see
  # what production starts.
  defp production_plugins do
    Application.fetch_env!(:whiq, Oban)
    |> Keyword.delete(:testing)
    |> Oban.Config.new()
    |> Map.fetch!(:plugins)
  end

  test "prunes finished jobs older than 7 days (RET-07)" do
    assert {Oban.Pruner, opts} = List.keyfind(production_plugins(), Oban.Pruner, 0)
    assert Keyword.fetch!(opts, :max_age) == {7, :days}
  end

  test "schedules the expired bin prune hourly (RET-04)" do
    assert {Oban.Cron, opts} = List.keyfind(production_plugins(), Oban.Cron, 0)
    assert {"@hourly", Whiq.Inspector.PruneExpiredBins} in Keyword.fetch!(opts, :crontab)
  end

  test "the application supervises Oban on the app repo (RET-04, RET-07)" do
    assert %Oban.Config{repo: Whiq.Repo} = Oban.config()
  end
end
