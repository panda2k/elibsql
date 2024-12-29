defmodule ElibSQL.Protocol do
  use DBConnection
  defstruct [:sock]

  def connect(opts) do
    hostname = Keyword.get(opts, :hostname, "localhost") |> String.to_charlist()
    port = Keyword.get(opts, :port, 443)
    timeout = Keyword.get(opts, :timeout, 5000)
    token = Keyword.get(opts, :token, System.get_env("TOKEN")) || raise "token is missing"
    sock_opts = [:binary, active: false, verify: :verify_none]

    :ssl.start()

    case :ssl.connect(hostname, port, sock_opts) do
      {:ok, sock} -> handshake(token, hostname, port, timeout, %__MODULE__{sock: sock})
      {:error, sock} -> {:error, "failed to open tcp"}
    end
  end

  defp upgrade_connection(hostname, port, timeout, state) do
    socket_key = :crypto.strong_rand_bytes(16) |> Base.encode64()

    handshake =
      "GET / HTTP/1.1\r\nHost: #{hostname}:#{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: #{socket_key}\r\nSec-WebSocket-Protocol: hrana3\r\nSec-WebSocket-Version: 13\r\n\r\n"

    with :ok <- :ssl.send(state.sock, handshake),
         {:ok, frame_back} = :ssl.recv(state.sock, 0),
         {:ok, 101, headers} <- frame_back |> parse_http,
         true = Map.get(headers, "Sec-WebSocket-Accept", ""),
         "websocket" = Map.get(headers, "Upgrade", ""),
         "Upgrade" = Map.get(headers, "Connection", "")
         do {:ok}
    else
      x -> {:error, x}
    end
  end

  defp handshake(token, hostname, port, timeout, state) do
    with :ok <- upgrade_connection(hostname, port, timeout, state)
        #  {:ok, frame_back} <- :ssl.recv(state.sock, 0),
        #  decoded_frame = frame_back |> parse_message do
        do {:ok}
        else
          {:error, x} -> {:error, x}
    end
  end

  def valid_websocket?(websocket_accept_header, key) do
    :crypto.hash(:sha, (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")) |> Base.encode64() |> String.equivalent?(websocket_accept_header)
  end

  @doc false
  def parse_http(response_bit_string) do
    case response_bit_string do
      <<"HTTP/1.1 ", status_code::binary-size(3), rest::binary>> ->
        case Integer.parse(status_code) do
          {status_code, _} when status_code >= 100 and status_code <= 599 ->
            header_dict =
              rest
              |> String.split("\r\n")
              |> Enum.drop(1)
              |> Enum.reduce_while(%{}, fn x, acc ->
                case String.split(x, ":", parts: 2) do
                  [""] -> {:halt, acc}
                  [key, value] -> {:cont, Map.put(acc, key, String.trim(value))}
                  _ -> {:halt, acc}
                end
              end)

            {:ok, status_code, header_dict}

          err -> {:error, err}
        end

      err ->
        {:error, err}
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
