defmodule Whiq.RateLimit do
  @moduledoc """
  Fixed-window rate limits kept in ETS (single node, AD-007). Windows align
  to wall-clock time, and denied hits still count within their window.
  """
  use Hammer, backend: :ets

  @doc """
  Counts one hit for `key` in the current `scale_ms` window. Returns `:ok`
  while the window holds at most `limit` hits, otherwise
  `{:error, retry_after_seconds}`: the whole seconds until the window
  resets, at least 1.
  """
  @spec check(term(), pos_integer(), pos_integer()) :: :ok | {:error, pos_integer()}
  def check(key, limit, scale_ms) do
    case hit(key, scale_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, ms_until_reset} -> {:error, max(1, ceil(ms_until_reset / 1000))}
    end
  end
end
