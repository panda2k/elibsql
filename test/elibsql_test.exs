defmodule ElibSQLTest do
  use ExUnit.Case
  doctest ElibSQL

  test "greets the world" do
    assert ElibSQL.hello() == :world
  end

  test "parses correct http websocket upgrade" do
    ElibSQL.Protocol.parse()
  end
end
