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
end
