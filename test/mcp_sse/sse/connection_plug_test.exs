defmodule SSE.ConnectionPlugTest do
  use ExUnit.Case, async: false

  # Add this to get conn test helpers for plugs
  import Plug.Conn
  import Plug.Test
  import ExUnit.CaptureLog

  alias MCP.Test.JsonRpcSchema

  alias SSE.ConnectionPlug
  alias SSE.ConnectionState
  alias SSE.SessionStorage.ETS

  @sse_path Application.compile_env(:mcp_sse, :sse_path)
  @message_path Application.compile_env(:mcp_sse, :message_path)

  @opts ConnectionPlug.init([])

  setup do
    # Clean up any existing data before each test to ensure isolation between tests
    :ets.delete_all_objects(ETS.table_name())

    on_exit(fn ->
      # Clean up any test data
      :ets.delete_all_objects(ETS.table_name())
    end)

    :ok
  end

  describe "handle_message/2" do
    setup do
      session_id = "test-session-#{:rand.uniform(1000)}"
      {:ok, state_pid} = ConnectionState.start_link(session_id)
      ETS.insert(session_id, self(), state_pid)

      # Build a test connection for a POST to the message path
      conn =
        conn(:post, @message_path, %{})
        |> Map.put(:query_params, %{"sessionId" => session_id})
        |> put_req_header("content-type", "application/json")

      %{conn: conn, session_id: session_id, state_pid: state_pid}
    end

    test "handles initialization message", %{conn: conn, state_pid: state_pid} do
      # First ensure the state is ready
      :ok = ConnectionState.handle_initialize(state_pid)

      message = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => "1",
        "params" => %{
          "protocolVersion" => "2024-11-05",
          "capabilities" => %{
            "version" => "1.0"
          }
        }
      }

      conn = %{conn | body_params: message}
      response = ConnectionPlug.call(conn, @opts)

      assert response.status == 202
      assert JSON.decode!(response.resp_body) == %{"status" => "ok"}
    end

    test "handles initialized notification", %{conn: conn, state_pid: state_pid} do
      # First ensure the state is initialized
      :ok = ConnectionState.handle_initialize(state_pid)

      message = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized"
      }

      conn = %{conn | body_params: message}
      response = ConnectionPlug.call(conn, @opts)

      assert response.status == 202
      assert JSON.decode!(response.resp_body) == %{"status" => "ok"}
    end

    test "handles cancelled notification", %{conn: conn} do
      message = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/cancelled",
        "params" => %{"reason" => "test"}
      }

      conn = %{conn | body_params: message}
      response = ConnectionPlug.call(conn, @opts)

      assert response.status == 202
      assert JSON.decode!(response.resp_body) == %{"status" => "ok"}
    end

    test "returns error for missing session", %{conn: conn} do
      conn = Map.put(conn, :query_params, %{})

      log =
        capture_log([level: :warning], fn ->
          response = ConnectionPlug.call(conn, @opts)

          assert response.status == 400
          assert JSON.decode!(response.resp_body) == %{"error" => "session_id is required"}
        end)

      assert log =~ "Missing session ID in request"
    end

    test "returns error for invalid session", %{conn: conn} do
      conn = Map.put(conn, :query_params, %{"sessionId" => ""})

      log =
        capture_log([level: :warning], fn ->
          response = ConnectionPlug.call(conn, @opts)

          assert response.status == 400
          assert JSON.decode!(response.resp_body) == %{"error" => "Invalid session ID"}
        end)

      assert log =~ "Invalid session ID provided"
    end

    test "returns error for session not found", %{conn: conn} do
      conn = Map.put(conn, :query_params, %{"sessionId" => "nonexistent"})

      log =
        capture_log([level: :warning], fn ->
          response = ConnectionPlug.call(conn, @opts)

          assert response.status == 404
          assert JSON.decode!(response.resp_body) == %{"error" => "Could not find session"}
        end)

      assert log =~ "Session not found: nonexistent"
    end

    test "returns error for invalid JSON-RPC message", %{conn: conn} do
      message = %{"invalid" => "message"}

      log =
        capture_log([level: :warning], fn ->
          conn = %{conn | body_params: message}
          response = ConnectionPlug.call(conn, @opts)

          assert response.status == 200

          response_body = JSON.decode!(response.resp_body)
          assert JsonRpcSchema.valid?(JsonRpcSchema.error_schema(), response_body)

          assert response_body["error"]["code"] == -32600
          assert response_body["error"]["message"] == "Could not parse message"
        end)

      assert log =~ "Invalid JSON-RPC message format"
    end
  end

  describe "SSE connection" do
    test "establishes SSE connection with correct headers" do
      conn =
        conn(:get, @sse_path)
        |> Map.put(:scheme, :http)
        |> Map.put(:host, "localhost")
        |> Map.put(:port, 4000)

      # Start the SSE connection in a separate process to avoid blocking the test
      spawn_link(fn ->
        response = ConnectionPlug.call(conn, @opts)
        send(self(), {:response, response})
      end)

      # Wait briefly for the connection to be established
      :timer.sleep(100)

      # Verify that a connection was established in the ETS table
      connections = :ets.tab2list(ETS.table_name())
      assert length(connections) == 1

      # Extract session_id from the connection entry
      [{session_id, _pid, _state_pid, _expires_at}] = connections

      # Clean up the connection
      ETS.delete(session_id)
    end
  end
end
