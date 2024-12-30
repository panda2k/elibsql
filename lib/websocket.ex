defmodule ElibSQL.Websocket do
  @typedoc "A websocket state"
  @type state() :: %__MODULE__{socket: :ssl.sslsocket(), timeout: pos_integer() | :infinity}

  defstruct [:socket, :timeout]
  import Kernel, except: [send: 2]

  @moduledoc """
  Websocket client for handling an Hrana3 connection
  """

  @doc """
  Opens and authenticates a websocket Hrana3 connection 

  ## Examples
  """
  @spec connect(String.t(), pos_integer(), binary(), pos_integer() | :infinity) ::
          {:ok, state()} | {:error, any()}
  def connect(hostname, port, token, timeout) when is_bitstring(hostname),
    do: connect(to_charlist(hostname), port, token, timeout)

  @spec connect(charlist(), pos_integer(), binary(), pos_integer() | :infinity) ::
          {:ok, state()} | {:error, any()}
  def connect(hostname, port, token, timeout) do
    sock_opts = [:binary, active: false, verify: :verify_none]

    with {:ok, socket} <- :ssl.connect(hostname, port, sock_opts),
         state = %__MODULE__{socket: socket, timeout: timeout},
         :ok <- upgrade_connection(state, hostname, port),
         :ok <- authenticate(state, token) do
      {:ok, state}
    end
  end

  @doc """
  Sends a message over the connection

  ## Examples
  """
  @spec send(state(), map()) :: :ok | {:error, any()}
  def send(state, data) do
    res =
      data
      |> JSON.encode!()
      |> IO.iodata_to_binary()
      |> binary_to_frame

    case res do
      {:ok, frame} -> :ssl.send(state.socket, frame)
      err -> err
    end
  end

  @doc """
  Recieves a message over the connection using the timeout defined in `state()`

  ## Examples
  """
  @spec recv(state()) :: {:ok, map() | list(any())}
  def recv(state), do: recv(state, state.timeout)

  @doc """
  Sends a message over the connection, overriding the timeout defined in `state()`

  ## Examples
  """
  @spec recv(state(), pos_integer() | :infinity) :: {:ok, map() | list(any())}
  def recv(state, timeout) do
    with {:ok, response_frame} <- :ssl.recv(state.socket, 0, timeout),
         {:ok, data_binary} <- parse_frame(response_frame),
         {:ok, data} <- JSON.decode(data_binary) do
      {:ok, data}
    end
  end

  @spec upgrade_connection(state(), charlist(), pos_integer()) :: :ok | {:error, any()}
  defp upgrade_connection(state, hostname, port) do
    socket_key = :crypto.strong_rand_bytes(16) |> Base.encode64()

    upgrade_request =
      "GET / HTTP/1.1\r\nHost: #{hostname}:#{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: #{socket_key}\r\nSec-WebSocket-Protocol: hrana3\r\nSec-WebSocket-Version: 13\r\n\r\n"

    with :ok <- :ssl.send(state.socket, upgrade_request),
         {:ok, frame_back} <- :ssl.recv(state.socket, 0, state.timeout),
         {:ok, 101, headers} <- frame_back |> parse_http,
         true <-
           Map.get(headers, "sec-websocket-accept", "") |> valid_websocket_accept?(socket_key) ||
             :error_invalid_accept,
         "websocket" <-
           Map.get(headers, "upgrade", "") |> String.downcase() || :error_invalid_upgrade,
         "upgrade" <-
           Map.get(headers, "connection", "") |> String.downcase() || :error_invalid_connection do
      :ok
    else
      err -> {:error, err}
    end
  end

  @spec authenticate(state(), binary()) :: :ok | {:error, any()}
  defp authenticate(state, token) do
    with :ok <- send(state, %{"type" => "hello", "jwt" => token}),
         {:ok, data} <- recv(state),
         "hello_ok" <- Map.get(data, "type") || :invalid_hello_response do
      :ok
    else
      err -> {:error, err}
    end
  end

  @spec binary_to_frame(binary()) :: {:ok, binary()} | {:error, :data_too_big}
  defp binary_to_frame(data) do
    # create the binary frame for the hello message
    # fin bit -> RSVs -> opcode -> masking bit -> 7 + 16 or 64 bits if needed -> mask key -> masked data
    case payload_length(data) do
      {:ok, length} ->
        {:ok, <<1::1, 0::3, 1::4, 1::1, length::bitstring, mask_data(data)::bitstring>>}

      err ->
        err
    end
  end

  @spec valid_websocket_accept?(String.t(), binary()) :: boolean()
  defp valid_websocket_accept?(websocket_accept_header, key) do
    :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    |> Base.encode64()
    |> String.equivalent?(websocket_accept_header)
  end

  @doc false
  @spec parse_http(bitstring()) ::
          {:ok, pos_integer(), %{String.t() => String.t()}} | {:error, any()}
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

  @spec parse_frame(bitstring()) :: {:ok, bitstring()} | {:error, any()}
  defp parse_frame(message) do
    <<_, second_byte, rest::binary>> = message

    case second_byte do
      len when len <= 125 ->
        {:ok, :binary.part(rest, 0, len)}

      len when len == 126 ->
        <<data_size::binary-size(2), data::binary>> = rest
        {:ok, :binary.part(data, 0, data_size)}

      len when len == 127 ->
        <<data_size::binary-size(4), data::binary>> = rest
        {:ok, :binary.part(data, 0, String.to_integer(data_size))}

      _ ->
        {:error, "invalid response"}
    end
  end

  @spec payload_length(bitstring()) :: {:ok, bitstring()} | {:error, :data_too_big}
  defp payload_length(data) do
    # final frame of message, rsvs to 0,
    small_size = 2 ** 7 - 3
    medium_size = 2 ** 16 - 1
    big_size = 2 ** 64 - 1

    case byte_size(data) do
      len when len <= small_size -> {:ok, <<len::7>>}
      len when len <= medium_size -> {:ok, <<126::7, len::16>>}
      len when len <= big_size -> {:ok, <<127::7, len::64>>}
      _ -> {:error, :data_too_big}
    end
  end

  @spec mask_data(bitstring()) :: bitstring()
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
end