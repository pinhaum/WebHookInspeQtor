defmodule WhiqWeb.BinNotFoundError do
  @moduledoc """
  Raised when `/bins/:token` names no live bin. Unknown, capture, expired and
  malformed tokens all map to the same 404, so the response never hints
  whether a token exists.
  """
  defexception message: "bin not found", plug_status: 404
end
