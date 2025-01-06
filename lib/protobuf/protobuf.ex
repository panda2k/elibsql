defmodule ElibSQL.Protobuf do
  @moduledoc """
  Protobuf encoder and decoder for Hrana messages
  """
  defstruct [:messages]

  @type t :: %__MODULE__{
          messages: %{binary() => ElibSQL.Protobuf.Parser.message()}
        }

  @doc """
  Decodes a binary into a map representing the corresponding
  message type
  """
  @spec decode(t(), binary(), binary()) :: {:ok, map()} | {:err, any()}
  def decode(state, data, message_type) do
    type = Map.get(state, message_type)
  end

  @doc """
  Encodes a map into the binary representing the corresponding 
  message type
  """
  @spec encode(t(), map(), binary()) :: {:ok, binary()} | {:err, any()}
  def encode(state, data, message_type) do
  end

  @doc """
  Decodes a binary to extract the first varint (returning it in 
  big endian) and also returns the remaining binary
  """
  @spec decode_varint(binary()) :: {:ok, bitstring(), binary()} | {:err, atom()}
  def decode_varint(<<>>, acc), do: {:error, :binary_unexpectedly_terminated}
  

  def decode_varint(<<0::1, data::bits-size(7), rest::binary>>, acc) do
    {:ok, <<data::bitstring, acc::bitstring>>, rest}
  end

  def decode_varint(<<1::1, data::bits-size(7), rest::binary>>, acc \\ <<>>) do
    decode_varint(rest, <<data::bitstring, acc::bitstring>>)
  end

  @doc """
  Converts a 2s complement bitstring to integer
  """
  def bitstring_to_int(<<>>, acc), do: acc

  def bitstring_to_int(<<first::1, rest::bitstring>>, acc \\ 0) do
    bitstring_to_int(rest, acc * 2 + first)
  end

  @doc """
  Converts a ZigZag binary to signed integer
  """
  def binary_to_sint(binary) do
  end

  @doc """
  Converts a binary to floating point (either double or float)
  """
  def binary_to_decimal(binary) do
  end
end
