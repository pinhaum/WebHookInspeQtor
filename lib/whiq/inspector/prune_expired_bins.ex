defmodule Whiq.Inspector.PruneExpiredBins do
  @moduledoc """
  Deletes expired bins and their requests (AD-006). Scheduled hourly by
  `Oban.Cron`; a failed run is retried by Oban and covered by the next one.
  """
  use Oban.Worker

  require Logger

  alias Whiq.Inspector

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    count = Inspector.delete_expired_bins()
    Logger.info("Pruned #{count} expired bins")
    :ok
  end
end
