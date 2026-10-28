defmodule Whiq.Inspector do
  @moduledoc """
  Creates and looks up bins. The web layer never touches `Whiq.Repo`
  for bins directly.
  """

  import Ecto.Query

  alias Whiq.Inspector.Bin
  alias Whiq.Inspector.CapturedRequest
  alias Whiq.Repo

  @ttl_days 7
  @token_format ~r/\A[A-Za-z0-9_-]{32}\z/

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

  @doc """
  Fetches an unexpired bin by its view token. A token outside the token
  format is rejected before any query runs.
  """
  def fetch_live_bin_by_view_token(token) when is_binary(token) do
    fetch_live_bin(:view_token, token)
  end

  @doc """
  Fetches an unexpired bin by its capture token. A token outside the token
  format is rejected before any query runs.
  """
  def fetch_live_bin_by_capture_token(token) when is_binary(token) do
    fetch_live_bin(:capture_token, token)
  end

  @doc """
  Stores a request captured by `bin`. The snapshot is a plain map built by
  the web layer (AD-004); headers are `[{name, value}]` in received order
  and are stored flattened (AD-008). `body_size` and `content_type` are
  derived here so they always agree with the stored bytes.
  """
  def capture_request(%Bin{} = bin, %{
        method: method,
        path: path,
        query_string: query_string,
        headers: headers,
        body: body,
        remote_ip: remote_ip
      }) do
    Repo.insert(%CapturedRequest{
      bin_id: bin.id,
      method: method,
      path: path,
      query_string: query_string,
      headers: Enum.flat_map(headers, fn {name, value} -> [name, value] end),
      body: body,
      body_size: byte_size(body),
      content_type: List.keyfind(headers, "content-type", 0, {nil, nil}) |> elem(1),
      remote_ip: remote_ip
    })
  end

  defp fetch_live_bin(field, token) do
    if token =~ @token_format do
      now = DateTime.utc_now(:second)

      Bin
      |> where([b], field(b, ^field) == ^token and b.expires_at > ^now)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        bin -> {:ok, bin}
      end
    else
      {:error, :not_found}
    end
  end

  # 24 random bytes encode to exactly 32 url-safe base64 characters.
  defp generate_token do
    24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
