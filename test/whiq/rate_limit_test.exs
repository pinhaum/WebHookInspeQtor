defmodule Whiq.RateLimitTest do
  use ExUnit.Case, async: true

  alias Whiq.RateLimit

  @hour :timer.hours(1)

  test "allows hits up to the limit and denies the next one with retry_after >= 1" do
    key = {:test, make_ref()}

    assert RateLimit.check(key, 3, @hour) == :ok
    assert RateLimit.check(key, 3, @hour) == :ok
    assert RateLimit.check(key, 3, @hour) == :ok
    assert {:error, retry_after} = RateLimit.check(key, 3, @hour)
    assert is_integer(retry_after)
    assert retry_after >= 1
    assert retry_after <= div(@hour, 1000)
  end

  test "two keys count independently" do
    limited = {:test, make_ref()}
    other = {:test, make_ref()}

    assert RateLimit.check(limited, 1, @hour) == :ok
    assert {:error, _retry_after} = RateLimit.check(limited, 1, @hour)

    assert RateLimit.check(other, 1, @hour) == :ok
  end

  # Hammer windows follow the wall clock and take no injected clock, so the
  # reset is observed by waiting out the interval the deny reported.
  test "LIM-07: after a deny, waiting the reported seconds allows the key again" do
    key = {:test, make_ref()}

    retry_after = hit_until_denied(key, 1, 1_000)
    Process.sleep(retry_after * 1_000)

    assert RateLimit.check(key, 1, 1_000) == :ok
  end

  defp hit_until_denied(key, limit, scale_ms, attempts \\ 10)

  defp hit_until_denied(_key, _limit, _scale_ms, 0), do: flunk("never denied")

  defp hit_until_denied(key, limit, scale_ms, attempts) do
    case RateLimit.check(key, limit, scale_ms) do
      :ok -> hit_until_denied(key, limit, scale_ms, attempts - 1)
      {:error, retry_after} -> retry_after
    end
  end
end
