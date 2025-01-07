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
end
