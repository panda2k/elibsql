defmodule ElibSQL.Protocol do
  use DBConnection
  defstruct [:sock, :timeout]

  def connect(opts) do
    hostname = Keyword.get(opts, :hostname, "localhost") |> String.to_charlist()
    port = Keyword.get(opts, :port, 443)
    timeout = Keyword.get(opts, :timeout, 5000)
    token = Keyword.get(opts, :token, System.get_env("TOKEN")) || raise "token is missing"
    sock_opts = [:binary, active: false, verify: :verify_none]

    case :ssl.connect(hostname, port, sock_opts) do
      {:ok, sock} -> handshake(token, hostname, port, timeout, %__MODULE__{sock: sock, timeout: timeout})
      {:error, _} -> {:error, "failed to open ssl tcp connection"}
    end
  end

  defp upgrade_connection(hostname, port, timeout, state) do
    socket_key = :crypto.strong_rand_bytes(16) |> Base.encode64()

    upgrade_request =
      "GET / HTTP/1.1\r\nHost: #{hostname}:#{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: #{socket_key}\r\nSec-WebSocket-Protocol: hrana3\r\nSec-WebSocket-Version: 13\r\n\r\n"

    with :ok <- :ssl.send(state.sock, upgrade_request),
         {:ok, frame_back} <- :ssl.recv(state.sock, 0, timeout),
         {:ok, 101, headers} <- frame_back |> parse_http,
         true <-
           Map.get(headers, "sec-websocket-accept", "") |> valid_websocket_accept?(socket_key) ||
             :error_invalid_accept,
         "websocket" <-
           Map.get(headers, "upgrade", "") |> String.downcase() || :error_invalid_upgrade,
         "upgrade" <-
           Map.get(headers, "connection", "") |> String.downcase() || :error_invalid_connection do
      {:ok, state}
    else
      x -> {:error, x}
    end
  end

  defp authenticate(token, timeout, state) do
    hello =
      %{
        "type" => "hello",
        "jwt" => token
      }
      |> :json.encode()
      |> IO.iodata_to_binary()

    # create the binary frame for the hello message
    # fin bit -> RSVs -> opcode -> masking bit -> 7 + 16 or 64 bits if needed -> mask key -> masked data
    frame =
      <<1::1, 0::3, 1::4, 1::1, payload_length(hello)::bitstring, mask_data(hello)::bitstring>>

    :ssl.send(state.sock, frame)
    {:ok, frame_back} = :ssl.recv(state.sock, 0, timeout)

    true =
      frame_back
      |> parse_websocket_frame()
      |> :json.decode()
      |> Map.get("type", "")
      |> String.equivalent?("hello_ok") ||
        :invalid_hello_response

    {:ok, state}
  end

  defp handshake(token, hostname, port, timeout, state) do
    with {:ok, state} <- upgrade_connection(hostname, port, timeout, state),
         {:ok, state} <- authenticate(token, timeout, state) do
      {:ok, state}
    end
  end

  def valid_websocket_accept?(websocket_accept_header, key) do
    :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    |> Base.encode64()
    |> String.equivalent?(websocket_accept_header)
  end

  @doc false
  def parse_http(response_bit_string) do
    with <<"HTTP/1.1 ", status_code::binary-size(3), rest::binary>> <- response_bit_string,
         {status_code, _} when status_code >= 100 and status_code <= 599 <-
           Integer.parse(status_code),
         header_dict <-
           rest
           |> String.split("\r\n")
           |> Enum.drop(1)
           |> Enum.reduce_while(%{}, fn x, acc ->
             case String.split(x, ":", parts: 2) do
               [""] -> {:halt, acc}
               [key, value] -> {:cont, Map.put(acc, String.downcase(key), String.trim(value))}
               _ -> {:halt, acc}
             end
           end) do
      {:ok, status_code, header_dict}
    else
      {num, _} when is_number(num) -> {:error, "found invalid status code #{num}"}
      err -> {:error, err}
    end
  end

  def parse_websocket_frame(message) do
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

  defp payload_length(data) do
    # final frame of message, rsvs to 0,
    small_size = 2 ** 7 - 3
    medium_size = 2 ** 16 - 1
    big_size = 2 ** 64 - 1

    case byte_size(data) do
      len when len <= small_size -> <<len::7>>
      len when len <= medium_size -> <<126::7, len::16>>
      len when len <= big_size -> <<127::7, len::64>>
      _ -> raise("Data way too big")
    end
  end

  defp mask_data(data) do
    masking_key = :crypto.strong_rand_bytes(4)

    masked_data =
      [
        data |> :binary.bin_to_list(),
        masking_key |> :binary.bin_to_list() |> Stream.cycle()
      ]
      |> Enum.zip()
      |> Enum.map(fn {data_byte, mask_byte} -> Bitwise.bxor(data_byte, mask_byte) end)
      |> :binary.list_to_bin()

    <<masking_key::binary, masked_data::binary>>
  end

  def handle_prepare(query, _opts, state) do
    # open the stream before sending
    stream_id = :crypto.strong_rand_bytes(4)
    open_stream =
      %{
        "type" => "open_stream",
        "stream_id" => stream_id
      }
      |> :json.encode()
      |> IO.iodata_to_binary()

    frame =
      <<1::1, 0::3, 1::4, 1::1, payload_length(open_stream)::bitstring, mask_data(open_stream)::bitstring>>

    with :ok <- :ssl.send(state.sock, frame),
      {:ok, frame_back} <- :ssl.recv(state.sock, 0, state.timeout),
      true <- frame_back
      |> parse_websocket_frame()
      |> :json.decode()
      |> Map.get("type", "")
      |> String.equivalent?("open_stream") ||
        :invalid_open_stream_response
      do
        query = %{query | statement_id: stream_id}

        {:ok, query, state}

    else
      err -> {:error, err}
    end
  end


  # def handle_execute() do

  # end



end
