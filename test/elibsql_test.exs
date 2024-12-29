defmodule ElibSQLTest do
  use ExUnit.Case
  doctest ElibSQL

  test "parses invalid HTTP response into error" do
    result =
      "HTTP/1.1 99 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"
      |> ElibSQL.Protocol.parse_http()

    assert result == {:error, "found invalid status code 99"}
  end

  test "parses valid HTTP response" do
    result =
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"
      |> ElibSQL.Protocol.parse_http()

    assert result ==
             {:ok, 101,
              %{
                "upgrade" => "websocket",
                "connection" => "Upgrade",
                "sec-websocket-accept" => "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
              }}
  end

  test "upgrade socket connection" do
    Dotenvy.source!([".env", System.get_env()])

    hostname = Dotenvy.env!("HOSTNAME", :string)
    port = 443
    timeout = 5000
    token = Dotenvy.env!("TOKEN", :string)

    {:ok, state} =
      ElibSQL.Protocol.connect(hostname: hostname, token: token, timeout: timeout, port: port)

    assert %ElibSQL.Protocol{} = state
  end
end
