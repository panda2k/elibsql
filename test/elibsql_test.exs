defmodule ElibSQLTest do
  use ExUnit.Case
  doctest ElibSQL

  test "execute dummy statement" do

    Dotenvy.source!([".env", System.get_env()])
    
    hostname = Dotenvy.env!("HOSTNAME", :string)
    port = 443
    timeout = 5000
    token = Dotenvy.env!("TOKEN", :string)

    {:ok, pid} = ElibSQL.start_link([hostname: hostname, port: port, timeout: timeout, token: token])
    ElibSQL.prepare_execute(pid, "SELECT ?", [42], [])
    |> IO.inspect
  end

end
