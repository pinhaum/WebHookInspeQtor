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

  A body longer than the `:max_body_bytes` config is stored cut to that
  many bytes with `body_truncated` set (AD-007).

  The bin keeps at most `:max_requests_per_bin` requests: the insert and the
  eviction of the oldest ones run in one transaction holding the bin row
  lock, so concurrent captures never exceed the cap. A bin deleted before
  the lock is taken returns `{:error, :not_found}`.

  After commit, the request is broadcast as `{:request_captured, request}`,
  then each evicted id as `{:request_evicted, id}`, to the bin's subscribers
  (see `subscribe/1`).
  """
  def capture_request(%Bin{} = bin, %{
        method: method,
        path: path,
        query_string: query_string,
        headers: headers,
        body: body,
        remote_ip: remote_ip
      }) do
    max_body_bytes = Application.fetch_env!(:whiq, :max_body_bytes)
    stored_body = binary_part(body, 0, min(byte_size(body), max_body_bytes))

    request = %CapturedRequest{
      bin_id: bin.id,
      method: method,
      path: path,
      query_string: query_string,
      headers: Enum.flat_map(headers, fn {name, value} -> [name, value] end),
      body: stored_body,
      body_size: byte_size(stored_body),
      body_truncated: byte_size(body) > max_body_bytes,
      content_type: List.keyfind(headers, "content-type", 0, {nil, nil}) |> elem(1),
      remote_ip: remote_ip
    }

    with {:ok, {request, evicted_ids}} <- insert_and_evict(bin, request) do
      Phoenix.PubSub.broadcast(Whiq.PubSub, topic(bin), {:request_captured, request})

      Enum.each(evicted_ids, fn id ->
        Phoenix.PubSub.broadcast(Whiq.PubSub, topic(bin), {:request_evicted, id})
      end)

      {:ok, request}
    end
  end

  defp insert_and_evict(%Bin{id: bin_id}, request) do
    max_requests = Application.fetch_env!(:whiq, :max_requests_per_bin)

    Repo.transact(fn ->
      locked = Repo.one(from(b in Bin, where: b.id == ^bin_id, select: b.id, lock: "FOR UPDATE"))

      if locked do
        request = Repo.insert!(request)

        beyond_cap =
          from(r in CapturedRequest,
            where: r.bin_id == ^bin_id,
            order_by: [desc: r.inserted_at, desc: r.id],
            offset: ^max_requests,
            select: r.id
          )

        {_count, evicted_ids} =
          Repo.delete_all(
            from(r in CapturedRequest, where: r.id in subquery(beyond_cap), select: r.id)
          )

        {:ok, {request, evicted_ids}}
      else
        {:error, :not_found}
      end
    end)
  end

  @doc """
  Subscribes the caller to the requests captured by `bin`.
  """
  def subscribe(%Bin{} = bin), do: Phoenix.PubSub.subscribe(Whiq.PubSub, topic(bin))

  @doc """
  Lists the bin's captured requests, newest first. Only the summary fields
  (`id`, `method`, `path`, `body_size`, `inserted_at`) are loaded; the rest
  are `nil`.
  """
  def list_requests(%Bin{id: bin_id}) do
    CapturedRequest
    |> where([r], r.bin_id == ^bin_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> select([r], struct(r, [:id, :method, :path, :body_size, :inserted_at]))
    |> Repo.all()
  end

  @doc """
  Fetches a full captured request, only when it belongs to `bin`.
  """
  def fetch_request(%Bin{id: bin_id}, id) when is_integer(id) do
    case Repo.get_by(CapturedRequest, id: id, bin_id: bin_id) do
      nil -> {:error, :not_found}
      request -> {:ok, request}
    end
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

  defp topic(%Bin{id: id}), do: "bin:#{id}"

  # 24 random bytes encode to exactly 32 url-safe base64 characters.
  defp generate_token do
    24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
