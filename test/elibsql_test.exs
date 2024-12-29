defmodule ElibSQLTest do
  use ExUnit.Case
  doctest ElibSQL

  test "greets the world" do
    assert ElibSQL.hello() == :world
  end

  test "parses correct http websocket upgrade" do
    result = "HTTP/1.1 99 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"
    |> ElibSQL.Protocol.parse_http()
    assert result == {:error}
  end

  test "parse expected HTTP response, parse response code + header" do
    result = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"
    |> ElibSQL.Protocol.parse_http()

    assert result == {:ok, 101, %{"Upgrade"=>"websocket", "Connection"=>"Upgrade", "Sec-WebSocket-Accept"=>"s3pPLMBiTxaQ9kYGzzhZRbK+xOo="}}
  end

  test "upgrade socket connection" do
    Dotenvy.source!([".env", System.get_env()])

    hostname = Dotenvy.env!("HOSTNAME", :string)
    port = 443
    timeout = 5000
    token = Dotenvy.env!("TOKEN", :string)

    result = ElibSQL.Protocol.connect([hostname: hostname, token: token, timeout: timeout, port: port])
    assert result == {:ok}
    # result = upgrade_connection(hostname, 443, 0, )
    # defp upgrade_connection(hostname, port, timeout, state) do

  end
end
