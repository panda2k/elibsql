defmodule ElibSQLTest do
  use ExUnit.Case
  doctest ElibSQL

  test "execute simple select statement" do
    Dotenvy.source!([".env", System.get_env()])

    hostname = Dotenvy.env!("HOSTNAME", :string)
    port = 443
    timeout = 5000
    token = Dotenvy.env!("TOKEN", :string)

    {:ok, pid} =
      ElibSQL.start_link(hostname: hostname, port: port, timeout: timeout, token: token)

    {:ok, query, result} = ElibSQL.prepare_execute(pid, "SELECT ?", [42], [])
    assert %ElibSQL.Query{} = query
    assert %ElibSQL.Result{} = result

    assert result == %ElibSQL.Result{
             columns: [%{"decltype" => nil, "name" => "?"}],
             rows: [[%{"type" => "integer", "value" => "42"}]]
           }
  end

  test "tokenize works on nicely formatted input" do
    contents =
      "message ClientMsg {\n  oneof msg {\n    HelloMsg hello = 1;\n    RequestMsg request = 2;\n  }\n}\n\n"

    tokens = ElibSQL.Protobuf.Parser.tokenize(contents)

    expected = [
      :message,
      "ClientMsg",
      :open_brace,
      :oneof,
      "msg",
      :open_brace,
      "HelloMsg",
      "hello",
      :equals,
      1,
      :semi_colon,
      "RequestMsg",
      "request",
      :equals,
      2,
      :semi_colon,
      :close_brace,
      :close_brace
    ]

    assert expected == tokens
  end

  test "tokenize works on input with comments" do
    contents =
      "//hello this is a comment\n/*\n now a block comment \n*/message ClientMsg {\n  oneof msg {\n    HelloMsg hello = 1;\n    RequestMsg request = 2;\n  }\n}\n\n"

    tokens = ElibSQL.Protobuf.Parser.tokenize(contents)

    expected = [
      :message,
      "ClientMsg",
      :open_brace,
      :oneof,
      "msg",
      :open_brace,
      "HelloMsg",
      "hello",
      :equals,
      1,
      :semi_colon,
      "RequestMsg",
      "request",
      :equals,
      2,
      :semi_colon,
      :close_brace,
      :close_brace
    ]

    assert expected == tokens
  end
end
