defmodule WhiqWeb.PageController do
  use WhiqWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
