defmodule WhiqWeb.BinControllerClientIPTest do
  # Mutates :whiq application env (:client_ip_header), so it cannot run
  # alongside other tests.
  use WhiqWeb.ConnCase, async: false

  alias Whiq.Inspector.Bin
  alias Whiq.Repo

  # Every request comes from the same proxy peer; only the header differs.
  @proxy_peer {172, 16, 0, 1}

  setup do
    previous = Application.fetch_env(:whiq, :client_ip_header)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:whiq, :client_ip_header, value)
        :error -> Application.delete_env(:whiq, :client_ip_header)
      end
    end)

    Application.put_env(:whiq, :client_ip_header, "fly-client-ip")
  end

  # The rate-limit ETS is shared across tests, so header values are unique
  # to this run and outside the 10.x range bin_controller_test.exs uses.
  defp unique_client_ip do
    n = System.unique_integer([:positive])
    "198.18.#{rem(div(n, 256), 256)}.#{rem(n, 256)}"
  end

  defp create_bin(client_ip) do
    %{build_conn() | remote_ip: @proxy_peer}
    |> put_req_header("fly-client-ip", client_ip)
    |> post(~p"/bins")
  end

  test "LIM-10: two clients behind the same proxy peer each create a bin" do
    first = create_bin(unique_client_ip())
    second = create_bin(unique_client_ip())

    assert redirected_to(first) =~ ~r"\A/bins/[A-Za-z0-9_-]{32}\z"
    assert redirected_to(second) =~ ~r"\A/bins/[A-Za-z0-9_-]{32}\z"
    assert Repo.aggregate(Bin, :count) == 2
  end

  test "LIM-09: a repeat from the same client header value is limited" do
    client_ip = unique_client_ip()
    assert redirected_to(create_bin(client_ip)) =~ ~r"\A/bins/[A-Za-z0-9_-]{32}\z"

    assert redirected_to(create_bin(client_ip)) == ~p"/"
    assert Repo.aggregate(Bin, :count) == 1
  end
end
