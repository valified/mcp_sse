defmodule SSE.SessionStorage.ETS do
  @moduledoc """
  ETS-based implementation of the SSE.SessionStorage behaviour.

  This module provides an ETS-based storage backend for SSE sessions.
  It creates and manages an ETS table for storing session information.

  ## Configuration

  You can configure the table name and session TTL in your application config:

      config :mcp_sse,
        ets_table_name: :my_custom_sse_connections,
        session_ttl: 86400 # Default TTL in seconds (1 day)
  """
  use GenServer
  @behaviour SSE.SessionStorage

  @table_name :mcp_sse_sessions

  @doc """
  Returns a child specification for starting the ETS storage under a supervisor.

  ## Parameters

  * `opts` - Options to pass to the GenServer

  ## Returns

  * A supervisor child specification
  """
  @impl SSE.SessionStorage
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc false
  @impl SSE.SessionStorage
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl GenServer
  def init(_opts) do
    table_name = Application.get_env(:mcp_sse, :ets_table_name, @table_name)
    table = :ets.new(table_name, [:set, :public, :named_table])

    schedule_cleanup()

    {:ok, %{table: table, table_name: table_name}}
  end

  @doc """
  Returns the table name used for storing SSE connections.

  The table name is used by other modules to interact with the ETS table
  that stores SSE connection information.

  ## Returns

    * `:mcp_sse_sessions` - The atom representing the ETS table name (or custom configured name)
  """
  def table_name do
    Application.get_env(:mcp_sse, :ets_table_name, @table_name)
  end

  @impl SSE.SessionStorage
  def insert(session_id, sse_pid, state_pid) do
    actual_ttl = SSE.SessionStorage.default_ttl()

    expires_at = :os.system_time(:seconds) + actual_ttl

    :ets.insert(table_name(), {session_id, sse_pid, state_pid, expires_at})

    :ok
  end

  @impl SSE.SessionStorage
  def lookup(session_id) do
    case :ets.lookup(table_name(), session_id) do
      [{^session_id, sse_pid, state_pid, expires_at}] ->
        current_time = :os.system_time(:seconds)

        if current_time < expires_at do
          {:ok, {sse_pid, state_pid}}
        else
          delete(session_id)

          {:error, :session_not_found}
        end

      # Handle sessions without expiration
      [{^session_id, sse_pid, state_pid}] ->
        {:ok, {sse_pid, state_pid}}

      [] ->
        {:error, :session_not_found}
    end
  end

  @impl SSE.SessionStorage
  def delete(session_id) do
    :ets.delete(table_name(), session_id)

    :ok
  end

  @impl SSE.SessionStorage
  def cleanup_expired do
    current_time = :os.system_time(:seconds)

    match_spec = [{{:"$1", :"$2", :"$3", :"$4"}, [{:<, :"$4", current_time}], [:"$1"]}]

    expired_sessions = :ets.select(table_name(), match_spec)

    Enum.each(expired_sessions, &delete/1)

    schedule_cleanup()

    :ok
  end

  defp schedule_cleanup do
    default_interval_ms = :timer.hours(1)

    cleanup_interval_ms = Application.get_env(:mcp_sse, :cleanup_interval_ms, default_interval_ms)

    Process.send_after(self(), :cleanup_expired_sessions, cleanup_interval_ms)
  end

  @impl GenServer
  def handle_info(:cleanup_expired_sessions, state) do
    cleanup_expired()

    {:noreply, state}
  end
end
