defmodule ElibSQL.Protocol do
  use DBConnection
  defstruct [:sock]

  def connect(opts) do
    hostname = Keyword.get(opts, :hostname, "localhost")
    port = Keyword.get(opts, :port, 443)
    timeout = Keyword.get(opts, :timeout, 5000)
    token = Keyword.get(opts, :token, System.get_env("TOKEN")) || raise "token is missing"
    sock_opts = [:binary, active: false, verify: :verify_none]

    :ssl.start()

    case :ssl.connect(hostname, port, sock_opts) do
      {:ok, sock} -> handshake(token, hostname, port, timeout, %__MODULE__{sock: sock})
      {:error, sock} -> {:error}
    end
  end

  defp upgrade_connection(hostname, port, timeout, state) do
    socket_key = :crypto.strong_rand_bytes(16) |> Base.encode64()

    handshake =
      "GET / HTTP/1.1\r\nHost: #{hostname}:#{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: #{socket_key}\r\nSec-WebSocket-Protocol: hrana3\r\nSec-WebSocket-Version: 13\r\n\r\n"

    with :ok <- :ssl.send(state.sock, handshake),
         {:ok, frame_back} = :ssl.recv(state.sock, 0),
         {:ok, status_code, headers} <- frame_back |> parse_message |> parse_http do 
    end
  end

  defp handshake(token, hostname, port, timeout, state) do
    handshake =
      "GET / HTTP/1.1\r\nHost: #{hostname}:#{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Protocol: hrana3\r\nSec-WebSocket-Version: 13\r\n\r\n"

    with :ok <- :ssl.send(state.sock, handshake),
         {:ok, frame_back} <- :ssl.recv(state.sock, 0),
         decoded_frame = frame_back |> parse_message do
    end
  end

  @doc false
  def parse_http(response_bit_string) do
    case response_bit_string do
      <<"HTTP/1.1 ", status_code::binary-size(3), rest::binary>> ->
        status_code = String.to_integer(status_code)

        header_dict =
          rest
          |> String.split("\r\n")
          |> Enum.drop(1)
          |> Enum.map(fn item ->
            case String.split(item, ":", parts: 2) do
              [key, value] -> {key, value}
              _ -> nil
            end
          end)
          |> Enum.reduce_while(%{}, fn x, acc ->
            case x do
              {key, value} -> {:cont, Map.put(acc, key, value)}
              nil -> {:halt, acc}
            end
          end)

        {:ok, status_code, header_dict}

      _ ->
        :error
    end
  end

  def parse_message(message) do
    <<_, second_byte, rest::binary>> = message

    case second_byte do
      len when len <= 125 ->
        :binary.part(rest, 0, len)

      len when len == 126 ->
        <<data_size::binary-size(2), data::binary>> = rest
        :binary.part(data, 0, data_size)

      len when len == 127 ->
        <<data_size::binary-size(4), data::binary>> = rest
        :binary.part(data, 0, String.to_integer(data_size))

      _ ->
        raise("Invalid response")
    end
  end
end
