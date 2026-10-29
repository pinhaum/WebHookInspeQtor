defmodule WhiqWeb.ShortReadAdapter do
  @moduledoc """
  A `Plug.Conn` adapter for tests whose `read_req_body/2` hands out a
  preset list of chunks one per call, ignoring `:length`, the way Bandit
  HTTP/2 can return a short `{:more, ...}`. Only the body callback exists;
  nothing else is called on a capture snapshot.
  """

  def conn(%Plug.Conn{} = conn, chunks) when is_list(chunks) do
    %{conn | adapter: {__MODULE__, chunks}}
  end

  def read_req_body([], _opts), do: {:ok, "", []}
  def read_req_body([last], _opts), do: {:ok, last, []}
  def read_req_body([chunk | rest], _opts), do: {:more, chunk, rest}
end
