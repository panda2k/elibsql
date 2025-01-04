defmodule ElibSQL.Protobuf do
  @moduledoc """
  Protobuf encoder and decoder for Hrana messages
  """
  defstruct [:messages]

  @type t :: %__MODULE__{
          messages: %{binary() => ElibSQL.Protobuf.Parser.message()}
        }
end
