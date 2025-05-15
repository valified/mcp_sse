defmodule SSE.SessionStorage do
  @moduledoc """
  Behaviour for SSE session storage backends.

  This module defines the behaviour that all session storage implementations must follow.
  It allows for pluggable storage backends, such as ETS, Redis, PostgreSQL, or any other
  storage mechanism that can implement these callbacks.

  ## Usage

  To implement a custom storage backend, create a module that implements this behaviour:

      defmodule MyApp.CustomSessionStorage do
        @behaviour SSE.SessionStorage

        # Implement all the required callbacks
        # ...
      end

  Then configure your application to use the custom storage:

      config :mcp_sse,
        session_storage: MyApp.CustomSessionStorage,
        session_ttl: 21_600

  ## Callbacks

  The following callbacks must be implemented by all storage backends:

  * `child_spec/1` - Returns the child specification for the storage backend
  * `start_link/1` - Starts the storage backend
  * `insert/4` - Stores a session with its associated SSE and state PIDs, with optional TTL
  * `lookup/1` - Retrieves a session by its ID
  * `delete/1` - Removes a session by its ID
  * `cleanup_expired/0` - Removes expired sessions (for backends without automatic expiration)
  """

  @doc """
  Returns the child specification for the storage backend.

  This function is called when the application starts and should return a valid
  child specification that can be used in a supervision tree.

  ## Parameters

  * `opts` - A keyword list of options for the storage backend

  ## Returns

  * A valid child specification map
  """
  @callback child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()

  @doc """
  Starts the storage backend.

  This function is called when the application starts and should initialize
  any resources needed by the storage backend.

  ## Parameters

  * `opts` - A keyword list of options for the storage backend

  ## Returns

  * `{:ok, pid}` - The PID of the started process
  * `{:error, reason}` - If the storage backend could not be started
  """
  @callback start_link(opts :: Keyword.t()) :: GenServer.on_start()

  @doc """
  Inserts a new session into the storage.

  ## Parameters

  * `session_id` - The unique identifier for the session
  * `sse_pid` - The PID of the SSE process
  * `state_pid` - The PID of the state process
  * `ttl` - Optional time-to-live in seconds (defaults to configured session_ttl)

  ## Returns

  * `:ok` - If the session was successfully inserted
  * `{:error, reason}` - If the session could not be inserted
  """
  @callback insert(
              session_id :: String.t(),
              sse_pid :: pid(),
              state_pid :: pid(),
              ttl :: non_neg_integer() | nil
            ) :: :ok | {:error, term()}

  @doc """
  Looks up a session by its ID.

  ## Parameters

  * `session_id` - The unique identifier for the session

  ## Returns

  * `{:ok, {sse_pid, state_pid}}` - If the session was found
  * `{:error, :session_not_found}` - If the session was not found
  """
  @callback lookup(session_id :: String.t()) ::
              {:ok, {pid(), pid()}} | {:error, :session_not_found}

  @doc """
  Deletes a session by its ID.

  ## Parameters

  * `session_id` - The unique identifier for the session

  ## Returns

  * `:ok` - If the session was successfully deleted
  * `{:error, reason}` - If the session could not be deleted
  """
  @callback delete(session_id :: String.t()) :: :ok | {:error, term()}

  @doc """
  Cleans up expired sessions.

  This is primarily for storage backends that don't have automatic expiration mechanisms.
  For backends with built-in expiration (like Redis), this can be a no-op.

  ## Returns

  * `:ok` - If the cleanup was successful
  * `{:error, reason}` - If there was an error during cleanup
  """
  @callback cleanup_expired() :: :ok | {:error, term()}

  @doc """
  Returns the configured session storage module.

  If no module is configured, defaults to `SSE.SessionStorage.ETS`.
  """
  def storage_module do
    Application.get_env(:mcp_sse, :session_storage, SSE.SessionStorage.ETS)
  end

  @doc """
  Returns the child specification for the configured storage module.

  This is a convenience function that can be used in a supervision tree.

  ## Parameters

  * `opts` - A keyword list of options for the storage backend

  ## Returns

  * A valid child specification map
  """
  def child_spec(opts \\ []) do
    storage_module().child_spec(opts)
  end

  @doc """
  Returns the configured default session TTL in seconds.

  If no TTL is configured, defaults to 86400 seconds (1 day).
  """
  def default_ttl do
    Application.get_env(:mcp_sse, :session_ttl, 86_400)
  end
end
