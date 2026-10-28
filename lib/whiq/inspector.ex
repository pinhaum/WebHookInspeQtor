defmodule Whiq.Inspector do
  @moduledoc """
  Creates and looks up bins. The web layer never touches `Whiq.Repo`
  for bins directly.
  """

  alias Whiq.Inspector.Bin
  alias Whiq.Repo

  @ttl_days 7

  @doc """
  Creates a bin with fresh capture and view tokens, expiring #{@ttl_days} days
  after creation (AD-006). A token collision raises on the unique index.
  """
  def create_bin do
    now = DateTime.utc_now(:second)

    Repo.insert(%Bin{
      capture_token: generate_token(),
      view_token: generate_token(),
      inserted_at: now,
      expires_at: DateTime.add(now, @ttl_days, :day)
    })
  end

  # 24 random bytes encode to exactly 32 url-safe base64 characters.
  defp generate_token do
    24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
