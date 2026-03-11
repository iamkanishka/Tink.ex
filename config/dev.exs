import Config

# =============================================================================
# Development Environment Configuration
# =============================================================================

# Configure TinkEx for development
config :tink_ex,
  # Use sandbox/test environment if available
  base_url: System.get_env("TINK_API_URL", "https://api.tink.com"),
  
  # Development credentials (use env vars or hardcode for local dev)
  client_id: System.get_env("TINK_CLIENT_ID"),
  client_secret: System.get_env("TINK_CLIENT_SECRET"),
  
  # Shorter timeouts for faster feedback during development
  timeout: 15_000,
  receive_timeout: 15_000,
  
  # Enable debug mode for verbose logging
  debug_mode: true,
  
  # Aggressive caching for faster development
  cache: [
    enabled: true,
    default_ttl: :timer.minutes(30),
    max_size: 500,
    # Longer TTLs in dev for better DX
    ttls: %{
      providers: :timer.hours(24),
      categories: :timer.hours(48),
      accounts: :timer.minutes(30),
      transactions: :timer.minutes(15),
      statistics: :timer.hours(2),
      credentials: :timer.minutes(2),
      balances: :timer.minutes(5),
      users: :timer.minutes(30)
    }
  ],
  
  # Enable retries in development
  retry: [
    enabled: true,
    max_attempts: 3,
    initial_delay: 500,
    max_delay: 5_000
  ]

# =============================================================================
# Development HTTP Pool - Smaller pool for dev
# =============================================================================

config :tink_ex, TinkEx.Finch,
  pools: %{
    default: [
      size: 10,
      count: 1,
      conn_opts: [
        timeout: 15_000
      ]
    ]
  }

# =============================================================================
# Development Logging - Verbose
# =============================================================================

config :logger, :console,
  format: "\n$time [$level] $metadata\n$message\n",
  metadata: [:request_id, :module, :function, :file, :line],
  level: :debug

# Log all HTTP requests in development
config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :debug]
  ]

# =============================================================================
# Development Tools
# =============================================================================

# Enable code reloading
if Code.ensure_loaded?(Mix) and Mix.env() == :dev do
  config :phoenix_live_reload,
    backend: :fs_poll,
    interval: 1000
end

# =============================================================================
# Development Telemetry
# =============================================================================

config :tink_ex, :telemetry,
  # Log all telemetry events in development
  log_events: true,
  events: [
    [:tink_ex, :request, :start],
    [:tink_ex, :request, :stop],
    [:tink_ex, :request, :exception],
    [:tink_ex, :cache, :hit],
    [:tink_ex, :cache, :miss],
    [:tink_ex, :retry, :attempt]
  ]

# =============================================================================
# Development OAuth/JWT
# =============================================================================

# Use test/development keys (never commit real keys!)
config :joken,
  default_signer: [
    signer_alg: "HS256",
    key_pem: System.get_env("JWT_SECRET", "dev-secret-key-change-in-production")
  ]

# =============================================================================
# Optional: Development Database (if using Ecto)
# =============================================================================

# Uncomment if you're using a database for caching or other purposes
# config :tink_ex, TinkEx.Repo,
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   database: "tink_ex_dev",
#   stacktrace: true,
#   show_sensitive_data_on_connection_error: true,
#   pool_size: 10

# =============================================================================
# Development Console Helpers
# =============================================================================

# Configure IEx for better development experience
config :iex,
  inspect: [
    pretty: true,
    limit: :infinity,
    width: 120
  ]
