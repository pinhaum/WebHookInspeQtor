defmodule WhiqWeb.BinLive do
  use WhiqWeb, :live_view

  alias Whiq.Inspector
  alias WhiqWeb.ByteFormat

  # The bin is kept for later reads, but the template must never render its
  # view token (BIN-11).
  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Inspector.fetch_live_bin_by_view_token(token) do
      {:ok, bin} ->
        # Subscribing before listing means a capture in between arrives twice;
        # stream_insert replaces it by DOM id.
        if connected?(socket), do: Inspector.subscribe(bin)
        requests = Inspector.list_requests(bin)

        {:ok,
         socket
         |> assign(
           bin: bin,
           capture_url: url(~p"/h/#{bin.capture_token}"),
           expires_at: DateTime.to_iso8601(bin.expires_at),
           request_count: length(requests),
           selected: newest(bin, requests)
         )
         |> stream(:requests, requests)}

      {:error, :not_found} ->
        raise WhiqWeb.BinNotFoundError
    end
  end

  defp newest(bin, requests) do
    with [newest | _] <- requests,
         {:ok, request} <- Inspector.fetch_request(bin, newest.id) do
      request
    else
      _ -> nil
    end
  end

  # A live arrival becomes the selection only when nothing is selected (LIVE-13).
  @impl true
  def handle_info({:request_captured, request}, socket) do
    socket =
      if socket.assigns.selected, do: socket, else: assign(socket, :selected, request)

    {:noreply,
     socket
     |> update(:request_count, &(&1 + 1))
     |> stream_insert(:requests, request, at: 0)}
  end

  # Captures broadcast before evictions, so when the selection is evicted the
  # newest remaining request is already on the page (LIVE-14).
  def handle_info({:request_evicted, id}, socket) do
    socket =
      socket
      |> stream_delete_by_dom_id(:requests, "requests-#{id}")
      |> update(:request_count, &(&1 - 1))

    selected = socket.assigns.selected

    if selected && selected.id == id do
      bin = socket.assigns.bin

      case newest(bin, Inspector.list_requests(bin)) do
        nil ->
          {:noreply, assign(socket, :selected, nil)}

        request ->
          {:noreply, socket |> assign(:selected, request) |> stream_insert(:requests, request)}
      end
    else
      {:noreply, socket}
    end
  end

  # The id comes from the client: anything that is not one of this bin's
  # request ids leaves the page unchanged.
  @impl true
  def handle_event("select", %{"id" => id}, socket) when is_binary(id) do
    with {id, ""} <- Integer.parse(id),
         {:ok, request} <- Inspector.fetch_request(socket.assigns.bin, id) do
      {:noreply, select(socket, request)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select", _params, socket), do: {:noreply, socket}

  # Rows only re-render when re-inserted, so both the old and the new
  # selection go back into the stream to move the highlight.
  defp select(socket, request) do
    previous = socket.assigns.selected
    socket = assign(socket, :selected, request)
    socket = if previous, do: stream_insert(socket, :requests, previous), else: socket
    stream_insert(socket, :requests, request)
  end

  defp selected?(selected, request), do: selected != nil and selected.id == request.id

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="bin-page" class="space-y-6">
        <div class="space-y-2">
          <label for="capture-url" class="text-sm font-semibold">Capture URL</label>
          <p class="text-sm opacity-70">Send any HTTP request here.</p>
          <div class="join w-full">
            <input
              id="capture-url"
              type="text"
              value={@capture_url}
              readonly
              class="join-item input w-full font-mono text-sm"
            />
            <button
              id="copy-capture-url"
              type="button"
              phx-click={JS.dispatch("whiq:copy", to: "#capture-url")}
              class="join-item btn btn-primary"
            >
              <.icon name="hero-clipboard-document" class="size-4" /> Copy
            </button>
          </div>
        </div>

        <p class="text-sm">
          Expires at
          <time id="expires-at" datetime={@expires_at} class="font-mono">{@expires_at}</time>
        </p>

        <p id="save-url-notice" role="note" class="alert alert-warning text-sm">
          <.icon name="hero-bookmark" class="size-5 shrink-0" />
          Save this page's URL: it is the only way back to this bin.
        </p>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
          <div class="space-y-2">
            <h2 class="text-sm font-semibold">Requests</h2>

            <div
              :if={@request_count == 0}
              id="empty-state"
              class="rounded-box border border-dashed border-base-300 p-6 text-sm space-y-2"
            >
              <p class="opacity-70">No requests yet. Send one:</p>
              <pre class="overflow-x-auto font-mono"><code id="empty-state-curl">curl -d 'hello' {@capture_url}</code></pre>
            </div>

            <ul id="requests" phx-update="stream" class="divide-y divide-base-300">
              <li :for={{dom_id, request} <- @streams.requests} id={dom_id}>
                <button
                  id={"#{dom_id}-select"}
                  type="button"
                  phx-click="select"
                  phx-value-id={request.id}
                  aria-current={selected?(@selected, request) && "true"}
                  class={[
                    "flex w-full items-center gap-3 rounded-field px-2 py-2 text-left font-mono text-sm transition-colors hover:bg-base-200",
                    selected?(@selected, request) && "bg-base-200 ring-1 ring-primary"
                  ]}
                >
                  <span id={"#{dom_id}-method"} class="badge badge-neutral">{request.method}</span>
                  <span id={"#{dom_id}-path"} class="flex-1 truncate">{request.path}</span>
                  <time id={"#{dom_id}-time"} class="opacity-70">
                    {DateTime.to_iso8601(request.inserted_at)}
                  </time>
                  <span id={"#{dom_id}-size"} class="opacity-70">{request.body_size} bytes</span>
                </button>
              </li>
            </ul>
          </div>

          <section
            :if={@selected}
            id="request-detail"
            class="space-y-4 rounded-box border border-base-300 p-4"
          >
            <dl class="grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-1 text-sm">
              <dt class="opacity-70">Method</dt>
              <dd id="detail-method" class="font-mono">{@selected.method}</dd>
              <dt class="opacity-70">Path</dt>
              <dd id="detail-path" class="font-mono break-all">{@selected.path}</dd>
              <dt class="opacity-70">Query string</dt>
              <dd id="detail-query" class="font-mono break-all">{@selected.query_string}</dd>
              <dt class="opacity-70">Content type</dt>
              <dd id="detail-content-type" class="font-mono break-all">
                {ByteFormat.printable(@selected.content_type)}
              </dd>
              <dt class="opacity-70">Remote IP</dt>
              <dd id="detail-remote-ip" class="font-mono">{@selected.remote_ip}</dd>
              <dt class="opacity-70">Received at</dt>
              <dd id="detail-time" class="font-mono">
                {DateTime.to_iso8601(@selected.inserted_at)}
              </dd>
              <dt class="opacity-70">Body size</dt>
              <dd id="detail-size" class="font-mono">{@selected.body_size} bytes</dd>
            </dl>

            <div class="space-y-1">
              <h3 class="text-sm font-semibold">Headers</h3>
              <ol id="request-headers" class="font-mono text-sm">
                <li
                  :for={
                    {[name, value], index} <-
                      @selected.headers |> Enum.chunk_every(2) |> Enum.with_index()
                  }
                  id={"request-header-#{index}"}
                  class="break-all"
                >
                  <span id={"request-header-#{index}-name"} class="font-semibold">
                    {ByteFormat.printable(name)}
                  </span>:
                  <span id={"request-header-#{index}-value"}>{ByteFormat.printable(value)}</span>
                </li>
              </ol>
            </div>

            <div class="space-y-1">
              <h3 class="text-sm font-semibold">Body</h3>
              <%= case ByteFormat.body(@selected.body) do %>
                <% :empty -> %>
                  <p id="request-body" data-format="empty" class="text-sm opacity-70">
                    (empty body)
                  </p>
                <% {:text, text} -> %>
                  <pre
                    id="request-body"
                    data-format="text"
                    class="overflow-x-auto rounded-box bg-base-200 p-3 font-mono text-sm whitespace-pre-wrap break-all"
                  >{text}</pre>
                <% {:hex, dump} -> %>
                  <pre
                    id="request-body"
                    data-format="hex"
                    class="overflow-x-auto rounded-box bg-base-200 p-3 font-mono text-sm"
                  >{dump}</pre>
              <% end %>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
