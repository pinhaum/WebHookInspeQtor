defmodule WhiqWeb.BinController do
  use WhiqWeb, :controller

  alias Whiq.Inspector

  def create(conn, _params) do
    {:ok, bin} = Inspector.create_bin()
    redirect(conn, to: ~p"/bins/#{bin.view_token}")
  end
end
