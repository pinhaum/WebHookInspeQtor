defmodule WhiqWeb.ProdForceSSLTest do
  # force_ssl is compile-time prod config, so the test endpoint never runs it.
  # Read the real config/prod.exs and drive Plug.SSL with exactly those options.
  use ExUnit.Case, async: true

  import Plug.Test

  @host "whiq.fly.dev"

  setup_all do
    opts =
      "config/prod.exs"
      |> Config.Reader.read!()
      |> get_in([:whiq, WhiqWeb.Endpoint, :force_ssl])
      |> Plug.SSL.init()

    %{ssl_opts: opts}
  end

  defp call(method, path, headers \\ [], opts) do
    conn = conn(method, "http://#{@host}#{path}")

    headers
    |> Enum.reduce(conn, fn {k, v}, conn -> Plug.Conn.put_req_header(conn, k, v) end)
    |> Plug.SSL.call(opts)
  end

  test "DEL-13: plain-HTTP GET /health passes through", %{ssl_opts: opts} do
    conn = call(:get, "/health", opts)

    refute conn.halted
    assert conn.status == nil
  end

  test "plain-HTTP GET / on localhost passes through", %{ssl_opts: opts} do
    conn = :get |> conn("http://localhost/") |> Plug.SSL.call(opts)

    refute conn.halted
    assert conn.status == nil
  end

  test "DEL-04: plain-HTTP GET / is redirected to https", %{ssl_opts: opts} do
    conn = call(:get, "/", opts)

    assert conn.halted
    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://#{@host}/"]
  end

  test "DEL-04: plain-HTTP POST /h/abc is redirected to https keeping the method", %{
    ssl_opts: opts
  } do
    conn = call(:post, "/h/abc", opts)

    assert conn.halted
    assert conn.status == 307
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://#{@host}/h/abc"]
  end

  test "DEL-04: GET / forwarded as https by the proxy passes through", %{ssl_opts: opts} do
    conn = call(:get, "/", [{"x-forwarded-proto", "https"}], opts)

    refute conn.halted
    assert conn.status == nil
  end
end
