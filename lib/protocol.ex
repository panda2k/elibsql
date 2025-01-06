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

  def ping(state) do
    case ElibSQL.Websocket.ping(state) do
      :ok -> {:ok, state}
      {:error, err} -> {:disconnect, err, state}
    end
  end

  @spec disconnect(any(), %ElibSQL.Websocket{socket: any(), timeout: :infinity | pos_integer()}) ::
          :ok
  def disconnect(_err, state) do
    ElibSQL.Websocket.disconnect(state)
    :ok
  end

  def checkout(state) do
    {:ok, state}
  end

  def handle_begin(_opts, _state) do
    raise "Not implemented"
  end

  def handle_close(query, _opts, state) do
    close_stream = %{
      "type" => "close_stream",
      "stream_id" => query.statement_id
    }

    with :ok <- ElibSQL.Websocket.send(state.websocket, close_stream),
         {:ok, data} <- ElibSQL.Websocket.recv(state),
         "close_stream" <- Map.get(data, "type") do
      {:ok, nil, state}
    else
      err -> {:error, err, state}
    end
  end

  def handle_commit(_opts, _state) do
    raise "Not implemented"
  end

  def handle_deallocate(_query, _cursor, _opts, _state) do
    raise "Not implemented"
  end

  def handle_declare(query, params, _opts, state) do
    cursor_id = :crypto.strong_rand_bytes(4)
    
    batch = %{
      "steps" => [
        %{
          "condition" => nil,
          "stmt" => %{
            "sql" => query.statement,
            "args" => params,
            "want_rows" => true
          }
        }
      ]
    }
  
    open_cursor = %{
      "type" => "open_cursor",
      "stream_id" => query.statement_id,
      "cursor_id" => cursor_id,
      "batch" => batch
    }
  
    with :ok <- ElibSQL.Websocket.send(state.websocket, open_cursor),
         {:ok, data} <- ElibSQL.Websocket.recv(state.websocket),
         "open_cursor" <- Map.get(data, "type") do
      cursor = %{cursor_id: cursor_id}
      {:ok, query, cursor, state}
    else
      {:error, reason} -> {:disconnect, reason, state}
      err -> {:error, err, state} # ?
    end
  end

  def handle_fetch(_query, _cursor, _opts, _state) do
    raise "Not implemented"
  end

  def handle_rollback(_opts, _state) do
    raise "Not implemented"
  end

  def handle_status(_opts, _state) do
    raise "Not implemented"
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
        query,
        params,
        _opts,
        state
      ) do
    # if stream_id good,
    # encode data to send, stment object looks like {query, params, true}
    execute_statement = %{
      "type" => "execute",
      "stream_id" => query.statement_id,
      "stmt" => %{
        "sql" => query.statement,
        "args" => params,
        "want_rows" => true
      }
    }

    close_stream = %{
      "type" => "close_stream",
      "stream_id" => query.statement_id
    }

    res =
      with :ok <- ElibSQL.Websocket.send(state.websocket, execute_statement),
           {:ok, data} <- ElibSQL.Websocket.recv(state.websocket),
           "execute" <- Map.get(data, "type"),
           %{
             "cols" => cols,
             "rows" => rows,
             "affected_row_count" => _affected_row_count,
             "last_insert_rowid" => _last_insert_rowid,
             "rows_read" => _rows_read,
             "rows_written" => _rows_written,
             "query_duration_ms" => _query_duration_ms
           } <-
             Map.get(data, "result") do
        result = %ElibSQL.Result{columns: cols, rows: rows}
        {:ok, query, result, state}
      end

    # no matter what happens we need to close stream after execution
    ElibSQL.Websocket.send(state.websocket, close_stream)
    res
  end
end
