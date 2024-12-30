defmodule ElibSQL.Protocol do
  use DBConnection
  defstruct [:websocket]

  def connect(opts) do
    hostname = Keyword.get(opts, :hostname, "localhost") |> String.to_charlist()
    port = Keyword.get(opts, :port, 443)
    timeout = Keyword.get(opts, :timeout, 5000)
    token = Keyword.get(opts, :token, System.get_env("TOKEN")) || raise "token is missing"

    case ElibSQL.Websocket.connect(hostname, port, token, timeout) do
      {:ok, websocket} -> {:ok, %__MODULE__{websocket: websocket}}
      err -> err
    end
  end

  def handle_prepare(query, _opts, state) do
    # open the stream before sending
    stream_id = :crypto.strong_rand_bytes(4)

    open_stream = %{
      "type" => "open_stream",
      "stream_id" => stream_id
    }

    close_stream = %{
      "type" => "close_stream",
      "stream_id" => stream_id
    }

    with :ok <- ElibSQL.Websocket.send(state.websocket, open_stream),
         {:ok, data} <- ElibSQL.Websocket.recv(state.websocket),
         "open_stream" <- data |> Map.get("type") || :invalid_open_stream_response do
      query = %{query | statement_id: stream_id}
      {:ok, query, state}
    else
      err ->
        # even if an error occurs, we must close the stream to reclaim the stream_id
        ElibSQL.Websocket.send(state.websocket, close_stream)
        {:error, err}
    end
  end

  def handle_execute(
        %ElibSQL.Query{statement: statement, statement_id: statement_id},
        params,
        _opts,
        state
      ) do
    # if stream_id good,
    # encode data to send, stment object looks like {query, params, true}
    execute_statement = %{
      "type" => "execute",
      "stream_id" => statement_id,
      "stmt" => %{
        "sql" => statement,
        "args" => params,
        "want_rows" => true
      }
    }

    with :ok <- ElibSQL.Websocket.send(state.websocket, execute_statement),
         {:ok, data} <- ElibSQL.Websocket.recv(state.websocket),
         "execute" <- Map.get(data, "type") do
      {:ok}
    end

    # %{"result" => result} <- decoded do
    #   columns = Map.get(result, "columns", [])
    #   rows = Map.get(result, "rows", [])
    #   affected_row_count = Map.get(result, "affected_row_count", 0)
    # {:ok, query, %{affected_row_count: affected_row_count, last_insert_rowid: last_insert_rowid, rows_read: rows_read,
    #     rows_written: rows_written, query_duration_ms: query_duration_ms},
    # {rows: rows, columns: columns, state}
    # with :ok <- :ssl.send(state.sock, frame),
    #     {:ok, frame_back} <- :ssl.recv(state.sock, 0, :infinity),
    #     response <- parse_websocket_frame(frame_back),
    #     {:ok, decoded} <- :json.decode(response),
    #     # extract data; if type = response_error, it fails; if type = execute, succeeded
    #     "execute" <- Map.get(decoded, "type", "") do
    # else
    #  {:error, err} -> {:error, err, state}
    #  err -> {:error, "handle_execute failed: #{inspect(err)}", state}
    # end
  end
end
