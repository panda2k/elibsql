defmodule ElibSQL.Query do
  @type t() :: %__MODULE__{
          statement: binary(),
          statement_id: integer()
        }
  defstruct [:statement, :statement_id]

  defimpl DBConnection.Query do
    def parse(query, _opts), do: query

    def describe(query, _opts), do: query

    def encode(_query, params, _opts), do: params

    def decode(_query, result, _opts), do: result
  end
end
