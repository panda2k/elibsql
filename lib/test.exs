defmodule Testing do
  def test do
    url = ~c'libsql-driver-panda2k.turso.io'
    port = 443
    handshake = "GET / HTTP/1.1\r\nHost: #{url}:#{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Protocol: hrana3\r\nSec-WebSocket-Version: 13\r\n\r\n"
    :ssl.start()
    {:ok, sock} = :ssl.connect(url, port, [:binary, active: false, verify: :verify_none])
    # send starting handshake
    :ssl.send(sock, handshake)
    {:ok, frame_back} = :ssl.recv(sock, 0)
    frame_back |> parse_message |> IO.inspect(binaries: :as_strings)
    # XOR mask the hello message payload according to websocket spec
    hello = %{
      "type" => "hello",
      "jwt" => "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3MzQ3NTQ3NjIsImlkIjoiYmFhMmI4OWEtNWEyOS00MGI2LWEzNTUtZDUxNmE5NTZlNjg3In0.ra87okNE0X6_gnvMOv_qXvEgfXmNgulZJiuqMNRJmqxnAWJ_GOiMODCyn4dvK3DT9CAgNVDdhMOWH--c-A2PDQ"
    } |> :json.encode() |> IO.iodata_to_binary
    # create the binary frame for the hello message
    # fin bit -> RSVs -> opcode -> masking bit -> 7 + 16 or 64 bits if needed -> mask key -> masked data
    frame = << 1::1, 0::3, 1::4, 1::1, payload_length(hello)::bitstring, mask_data(hello)::bitstring >>
    :ssl.send(sock, frame)
    # decode the response
    {:ok, frame_back} = :ssl.recv(sock, 0)
    frame_back |> parse_message |> IO.inspect(binaries: :as_strings)
  end

  def parse_message (message) do
    << _, second_byte, rest::binary >> = message
    case second_byte do
      len when len <= 125 -> rest
      len when len == 126 ->
        << _::binary-size(2), data >> = rest
        data
      len when len == 127 ->
        << _::binary-size(4), data >> = rest
        data
      _ -> raise("Invalid response")
    end
  end



  def mask_data (data) do
    masking_key = :crypto.strong_rand_bytes(4)
    masked_data = [
      data |> :binary.bin_to_list,
      masking_key |> :binary.bin_to_list |> Stream.cycle
    ]
    |> Enum.zip
    |> Enum.map(fn { data_byte, mask_byte } -> Bitwise.bxor(data_byte, mask_byte) end)
    |> :binary.list_to_bin
    << masking_key::binary, masked_data::binary >>
  end

  def payload_length (data) do
    # final frame of message, rsvs to 0,
    small_size = 2 ** 7 - 3
    medium_size = 2 ** 16 - 1
    big_size = 2 ** 64 - 1
    case byte_size(data) do
      len when len <= small_size -> << len::7 >>
      len when len <= medium_size -> << 126::7, len::16 >>
      len when len <= big_size -> << 127::7, len::64 >>
      _ -> raise("Data way too big")
    end
  end
end

Testing.test
