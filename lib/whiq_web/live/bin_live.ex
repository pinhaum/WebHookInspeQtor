defmodule WhiqWeb.BinLive do
  use WhiqWeb, :live_view

  alias Whiq.Inspector

  # Only derived values are assigned: the view token must never reach the page (BIN-11).
  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Inspector.fetch_live_bin_by_view_token(token) do
      {:ok, bin} ->
        {:ok,
         assign(socket,
           capture_url: url(~p"/h/#{bin.capture_token}"),
           expires_at: DateTime.to_iso8601(bin.expires_at)
         )}

      {:error, :not_found} ->
        raise WhiqWeb.BinNotFoundError
    end
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
      </section>
    </Layouts.app>
    """
  end
end
