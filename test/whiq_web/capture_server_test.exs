defmodule WhiqWeb.CaptureServerTest do
  # Drives a real Bandit listener over TCP for what ConnTest cannot reach:
  # chunked framing and socket read timeouts. The server runs outside the
  # test process, so the sandbox must be shared.
  use Whiq.DataCase, async: false

  # Bandit logs the read-timeout error it answers with 408.
  @moduletag :capture_log

  alias Whiq.Inspector
  alias Whiq.Inspector.CapturedRequest

  setup do
    server = start_supervised!({Bandit, plug: WhiqWeb.Endpoint, ip: :loopback, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    {:ok, bin} = Inspector.create_bin()
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :line])
    on_exit(fn -> :gen_tcp.close(socket) end)

    %{bin: bin, socket: socket}
  end

  defp status_line(socket) do
    {:ok, line} = :gen_tcp.recv(socket, 0, 5_000)
    line
  end

  defp await_close(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, _rest} -> await_close(socket)
      {:error, :closed} -> :ok
    end
  end

  defp stored_requests(bin) do
    Repo.all(from r in CapturedRequest, where: r.bin_id == ^bin.id)
  end

  test "CAP-08: a chunked body is stored de-chunked", %{bin: bin, socket: socket} do
    :ok =
      :gen_tcp.send(
        socket,
        "POST /h/#{bin.capture_token} HTTP/1.1\r\nhost: localhost\r\n" <>
          "content-type: text/plain\r\ntransfer-encoding: chunked\r\n\r\n"
      )

    :ok = :gen_tcp.send(socket, "5\r\nhello\r\n")
    :ok = :gen_tcp.send(socket, "1\r\n \r\n")
    :ok = :gen_tcp.send(socket, "5\r\nworld\r\n0\r\n\r\n")

    assert status_line(socket) == "HTTP/1.1 200 OK\r\n"
    assert [%CapturedRequest{body: "hello world"}] = stored_requests(bin)
  end

  test "CAP-19: a body that stalls past the read timeout is answered 408 and not stored",
       %{bin: bin, socket: socket} do
    :ok =
      :gen_tcp.send(
        socket,
        "POST /h/#{bin.capture_token} HTTP/1.1\r\nhost: localhost\r\n" <>
          "content-type: text/plain\r\ncontent-length: 10\r\n\r\nabc"
      )

    assert "HTTP/1.1 408 " <> _reason = status_line(socket)
    # Bandit logs and closes after the 408; waiting for the close keeps the log in this test.
    await_close(socket)

    assert stored_requests(bin) == []
  end
end
