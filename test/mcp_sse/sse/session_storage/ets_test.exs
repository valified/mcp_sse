defmodule SSE.SessionStorage.ETSTest do
  use ExUnit.Case, async: true

  alias SSE.SessionStorage.ETS

  # Helper function to mark a session as expired
  defp mark_session_as_expired(session_id, sse_pid, state_pid, seconds_ago \\ 10) do
    past_time = :os.system_time(:seconds) - seconds_ago
    :ets.insert(ETS.table_name(), {session_id, sse_pid, state_pid, past_time})
  end

  setup do
    pid =
      case ETS.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    test_sse_pid =
      spawn(fn ->
        receive do
          _ -> :ok
        end
      end)

    test_state_pid =
      spawn(fn ->
        receive do
          _ -> :ok
        end
      end)

    on_exit(fn ->
      Process.exit(test_sse_pid, :normal)
      Process.exit(test_state_pid, :normal)

      table_name = ETS.table_name()

      if :ets.info(table_name) != :undefined do
        :ets.delete_all_objects(table_name)
      end
    end)

    # Return the test context
    %{
      server: pid,
      sse_pid: test_sse_pid,
      state_pid: test_state_pid,
      session_id: "test-session-#{:rand.uniform(1000)}"
    }
  end

  describe "child_spec/1" do
    test "returns a valid child specification" do
      opts = [test: :option]
      spec = ETS.child_spec(opts)

      assert spec.id == ETS
      assert spec.start == {ETS, :start_link, [opts]}
      assert spec.type == :worker
      assert spec.restart == :permanent
      assert spec.shutdown == 5000
    end
  end

  describe "table_name/0" do
    test "returns the configured table name or default" do
      original_name = Application.get_env(:mcp_sse, :ets_table_name)

      on_exit(fn ->
        if original_name do
          Application.put_env(:mcp_sse, :ets_table_name, original_name)
        else
          Application.delete_env(:mcp_sse, :ets_table_name)
        end
      end)

      custom_name = :custom_sse_table
      Application.put_env(:mcp_sse, :ets_table_name, custom_name)
      assert ETS.table_name() == custom_name

      Application.delete_env(:mcp_sse, :ets_table_name)
      assert ETS.table_name() == :mcp_sse_sessions
    end
  end

  describe "insert/4" do
    test "stores a session with default TTL", %{
      sse_pid: sse_pid,
      state_pid: state_pid,
      session_id: session_id
    } do
      assert :ok = ETS.insert(session_id, sse_pid, state_pid)

      assert {:ok, {^sse_pid, ^state_pid}} = ETS.lookup(session_id)
    end

    test "stores a session with custom TTL", %{
      sse_pid: sse_pid,
      state_pid: state_pid,
      session_id: session_id
    } do
      ttl = 1111
      current_time = :os.system_time(:seconds)

      assert :ok = ETS.insert(session_id, sse_pid, state_pid, ttl)

      [{^session_id, ^sse_pid, ^state_pid, expires_at}] =
        :ets.lookup(ETS.table_name(), session_id)

      assert_in_delta expires_at, current_time + ttl, 1

      assert {:ok, {^sse_pid, ^state_pid}} = ETS.lookup(session_id)
    end

    test "expires sessions after TTL", %{
      sse_pid: sse_pid,
      state_pid: state_pid,
      session_id: session_id
    } do
      ttl = 10

      assert :ok = ETS.insert(session_id, sse_pid, state_pid, ttl)

      assert {:ok, {^sse_pid, ^state_pid}} = ETS.lookup(session_id)

      mark_session_as_expired(session_id, sse_pid, state_pid)

      assert {:error, :session_not_found} = ETS.lookup(session_id)
    end
  end

  describe "lookup/1" do
    test "returns session when found", %{
      sse_pid: sse_pid,
      state_pid: state_pid,
      session_id: session_id
    } do
      :ok = ETS.insert(session_id, sse_pid, state_pid)

      assert {:ok, {^sse_pid, ^state_pid}} = ETS.lookup(session_id)
    end

    test "returns error when session not found" do
      assert {:error, :session_not_found} = ETS.lookup("non-existent-session")
    end

    test "handles legacy sessions without expiration", %{
      sse_pid: sse_pid,
      state_pid: state_pid,
      session_id: session_id
    } do
      :ets.insert(ETS.table_name(), {session_id, sse_pid, state_pid})

      assert {:ok, {^sse_pid, ^state_pid}} = ETS.lookup(session_id)
    end
  end

  describe "delete/1" do
    test "removes a session", %{
      sse_pid: sse_pid,
      state_pid: state_pid,
      session_id: session_id
    } do
      :ok = ETS.insert(session_id, sse_pid, state_pid)

      assert {:ok, {^sse_pid, ^state_pid}} = ETS.lookup(session_id)

      assert :ok = ETS.delete(session_id)

      assert {:error, :session_not_found} = ETS.lookup(session_id)
    end

    test "returns ok even if session doesn't exist" do
      assert :ok = ETS.delete("non-existent-session")
    end
  end

  describe "cleanup_expired/0" do
    test "removes expired sessions", %{
      sse_pid: sse_pid,
      state_pid: state_pid
    } do
      expired_session = "expired-session"
      valid_session = "valid-session"

      :ok = ETS.insert(expired_session, sse_pid, state_pid, 10)

      mark_session_as_expired(expired_session, sse_pid, state_pid)

      :ok = ETS.insert(valid_session, sse_pid, state_pid, 3600)

      assert :ok = ETS.cleanup_expired()

      assert {:error, :session_not_found} = ETS.lookup(expired_session)

      assert {:ok, {^sse_pid, ^state_pid}} = ETS.lookup(valid_session)
    end
  end
end
