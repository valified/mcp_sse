import Config

# Set log level to warn for tests to reduce noise
config :logger, level: :info

# Set the paths for testing customization
config :mcp_sse, :sse_path, "/mcp/sse"
config :mcp_sse, :message_path, "/mcp/msg"
