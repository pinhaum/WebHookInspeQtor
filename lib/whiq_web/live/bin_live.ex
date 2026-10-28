defmodule WhiqWeb.BinLive do
  use WhiqWeb, :live_view

  alias Whiq.Inspector

  # Only derived values are assigned: the view token must never reach the page (BIN-11).
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
           capture_url: url(~p"/h/#{bin.capture_token}"),
           expires_at: DateTime.to_iso8601(bin.expires_at),
           request_count: length(requests)
         )
         |> stream(:requests, requests)}

      {:error, :not_found} ->
        raise WhiqWeb.BinNotFoundError
    end
  end

  @impl true
  def handle_info({:request_captured, request}, socket) do
    {:noreply,
     socket
     |> update(:request_count, &(&1 + 1))
     |> stream_insert(:requests, request, at: 0)}
  end

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
            <li
              :for={{dom_id, request} <- @streams.requests}
              id={dom_id}
              class="flex items-center gap-3 py-2 font-mono text-sm"
            >
              <span id={"#{dom_id}-method"} class="badge badge-neutral">{request.method}</span>
              <span id={"#{dom_id}-path"} class="flex-1 truncate">{request.path}</span>
              <time id={"#{dom_id}-time"} class="opacity-70">
                {DateTime.to_iso8601(request.inserted_at)}
              </time>
              <span id={"#{dom_id}-size"} class="opacity-70">{request.body_size} bytes</span>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
