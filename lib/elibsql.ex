defmodule ElibSQL do
  @moduledoc """
  Documentation for `ElibSQL`.
  """

  @doc """
  Start link
  """
  def start_link(opts) do
    DBConnection.start_link(ElibSQL.Protocol, opts)
  end

  @doc """
  Prepare execute
  """
  def prepare_execute(conn, statement, params, opts) do
    query = %ElibSQL.Query{statement: statement}
    DBConnection.prepare_execute(conn, query, params, opts)
  end
end
