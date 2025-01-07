defmodule ProtobufTest do
  use ExUnit.Case
  doctest ElibSQL.Protobuf

  test "decode varint" do
    input = <<0x96, 0x1>>
    assert ElibSQL.Protobuf.decode_varint(input) == {:ok, <<2, 22::6>>, <<>>}
  end

  test "bitstring to int" do
    input = <<2, 22::6>>
    assert ElibSQL.Protobuf.bitstring_to_int(input) == 150
  end
end
