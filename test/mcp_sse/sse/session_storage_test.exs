defmodule SSE.SessionStorageTest do
  use ExUnit.Case, async: true

  defmodule MockStorage do
    @behaviour SSE.SessionStorage

    def child_spec(opts), do: %{id: __MODULE__, opts: opts}
    def start_link(_), do: {:ok, self()}
    def insert(_, _, _), do: :ok
    def insert_with_ttl(_, _, _, _), do: :ok
    def lookup(_), do: {:ok, {self(), self()}}
    def delete(_), do: :ok
    def cleanup_expired, do: :ok
  end

  describe "storage_module/0" do
    test "returns the configured storage module" do
      original_config = Application.get_env(:mcp_sse, :session_storage)

      on_exit(fn ->
        if original_config do
          Application.put_env(:mcp_sse, :session_storage, original_config)
        else
          Application.delete_env(:mcp_sse, :session_storage)
        end
      end)

      Application.put_env(:mcp_sse, :session_storage, SSE.SessionStorage.ETS)
      assert SSE.SessionStorage.storage_module() == SSE.SessionStorage.ETS

      Application.put_env(:mcp_sse, :session_storage, MockStorage)
      assert SSE.SessionStorage.storage_module() == MockStorage

      Application.delete_env(:mcp_sse, :session_storage)
      assert SSE.SessionStorage.storage_module() == SSE.SessionStorage.ETS
    end
  end

  describe "child_spec/1" do
    test "delegates to the configured storage module" do
      original_config = Application.get_env(:mcp_sse, :session_storage)

      on_exit(fn ->
        if original_config do
          Application.put_env(:mcp_sse, :session_storage, original_config)
        else
          Application.delete_env(:mcp_sse, :session_storage)
        end
      end)

      Application.put_env(:mcp_sse, :session_storage, MockStorage)

      assert SSE.SessionStorage.child_spec() == %{id: MockStorage, opts: []}

      opts = [test: :option]
      assert SSE.SessionStorage.child_spec(opts) == %{id: MockStorage, opts: opts}
    end
  end

  describe "default_ttl/0" do
    test "returns the configured TTL or default" do
      original_ttl = Application.get_env(:mcp_sse, :session_ttl)

      on_exit(fn ->
        if original_ttl do
          Application.put_env(:mcp_sse, :session_ttl, original_ttl)
        else
          Application.delete_env(:mcp_sse, :session_ttl)
        end
      end)

      Application.put_env(:mcp_sse, :session_ttl, 3600)
      assert SSE.SessionStorage.default_ttl() == 3600

      Application.delete_env(:mcp_sse, :session_ttl)
      assert SSE.SessionStorage.default_ttl() == 86_400
    end
  end
end
