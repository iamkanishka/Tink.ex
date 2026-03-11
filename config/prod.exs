import Config

# =============================================================================
# Production Environment Configuration
# =============================================================================

# NOTE: This file is loaded at compile time.
# For runtime configuration (reading from environment variables),
# use config/runtime.exs instead.

# Configure TinkEx for production
config :tink_ex,
  # Production API URL
  base_url: "https://api.tink.com",
  
  # Production timeouts - be generous
  timeout: 30_000,
  receive_timeout: 30_000,
  
  # Use production HTTP adapter
  http_adapter: TinkEx.HTTPAdapter,
  
  # Conservative caching in production
  cache: [
    enabled: true,
    default_ttl: :timer.minutes(5),
    max_size: 5000,
    # Production TTLs - conservative
    ttls: %{
      providers: :timer.hours(1),
      categories: :timer.hours(24),
      accounts: :timer.minutes(5),
      transactions: :timer.minutes(3),
      statistics: :timer.hours(1),
      credentials: :timer.seconds(30),
      balances: :timer.minutes(1),
      users: :timer.minutes(10)
    }
  ],
  
  # Enable retries in production
  retry: [
    enabled: true,
    max_attempts: 3,
    backoff_multiplier: 2,
    initial_delay: 1_000,
    max_delay: 10_000,
    retry_on_status: [429, 500, 502, 503, 504],
    retry_on_errors: [:timeout, :network_error, :connection_closed]
  ],
  
  # Enable rate limiting in production
  rate_limit: [
    enabled: true,
    max_requests: 100,
    interval: :timer.seconds(60),
    # Strategy: :stop_and_wait or :drop
    strategy: :stop_and_wait
  ],
  
  # Disable debug mode in production
  debug_mode: false

# =============================================================================
# Production HTTP Pool - Optimized for load
# =============================================================================

config :tink_ex, TinkEx.Finch,
  pools: %{
    default: [
      # Larger pool for production traffic
      size: 100,
      # Multiple pools for better distribution
      count: System.schedulers_online(),
      # Connection settings
      conn_opts: [
        timeout: 30_000,
        # Production TLS/SSL settings
        transport_opts: [
          verify: :verify_peer,
          depth: 3,
          # Enable certificate verification in production
          cacerts: :public_key.cacerts_get(),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ],
          # TLS 1.2 minimum
          versions: [:"tlsv1.2", :"tlsv1.3"]
        ]
      ],
      # Pool settings optimized for production
      pool_opts: [
        max_idle_time: :timer.minutes(5),
        protocol: :http2  # Use HTTP/2 in production
      ]
    ]
  }

# =============================================================================
# Production Logging
# =============================================================================

config :logger,
  level: :info,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :error]

# =============================================================================
# Production Telemetry
# =============================================================================

config :tink_ex, :telemetry,
  # Don't log events in production (use telemetry reporters instead)
  log_events: false,
  events: [
    [:tink_ex, :request, :stop],
    [:tink_ex, :request, :exception],
    [:tink_ex, :cache, :hit],
    [:tink_ex, :cache, :miss]
  ]

# =============================================================================
# Production Security
# =============================================================================

# Force HTTPS in production
config :tink_ex, :security,
  force_https: true,
  # Validate SSL certificates
  validate_ssl: true,
  # Maximum request size (10MB)
  max_request_size: 10_485_760

# =============================================================================
# Production Performance
# =============================================================================

config :tink_ex, :performance,
  # Enable connection pooling
  pool_connections: true,
  # Enable HTTP/2
  http2: true,
  # Enable request compression
  compress_requests: true,
  # Enable response compression
  compress_responses: true

# =============================================================================
# Production Monitoring
# =============================================================================

# Configure error reporting (e.g., Sentry, AppSignal)
# Uncomment and configure based on your monitoring service

# Sentry
# config :sentry,
#   dsn: System.get_env("SENTRY_DSN"),
#   environment_name: :prod,
#   enable_source_code_context: true,
#   root_source_code_path: File.cwd!(),
#   tags: %{
#     env: "production",
#     app: "tink_ex"
#   },
#   included_environments: [:prod]

# AppSignal
# config :appsignal, :config,
#   active: true,
#   name: "TinkEx",
#   push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY"),
#   env: :prod

# =============================================================================
# Production Database (if using Ecto)
# =============================================================================

# Uncomment if using a database
# config :tink_ex, TinkEx.Repo,
#   pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
#   queue_target: 5_000,
#   queue_interval: 10_000

# =============================================================================
# SSL Configuration
# =============================================================================

# Ensure SSL/TLS is properly configured
config :ssl,
  protocol_version: [:"tlsv1.2", :"tlsv1.3"],
  verify: :verify_peer,
  fail_if_no_peer_cert: true

# =============================================================================
# Runtime Configuration Notice
# =============================================================================

# IMPORTANT: Sensitive configuration (API keys, secrets) should be
# loaded at runtime from environment variables.
# See config/runtime.exs for runtime configuration.
