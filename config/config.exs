import Config

# Base configuration for TinkEx library
# Environment-specific configs are in dev.exs, test.exs, prod.exs

# =============================================================================
# TinkEx Core Configuration
# =============================================================================

config :tink_ex,
  # API Base URL
  base_url: "https://api.tink.com",
  
  # HTTP Client Settings
  http_adapter: TinkEx.HTTPAdapter,
  timeout: 30_000,
  receive_timeout: 30_000,
  
  # Rate Limiting (optional - requires hammer dependency)
  rate_limit: [
    enabled: false,
    max_requests: 100,
    interval: :timer.seconds(60)
  ],
  
  # Cache Settings (optional - requires cachex dependency)
  cache: [
    enabled: true,
    default_ttl: :timer.minutes(5),
    max_size: 1000,
    # Resource-specific TTLs (in milliseconds)
    ttls: %{
      providers: :timer.hours(1),
      categories: :timer.hours(24),
      accounts: :timer.minutes(5),
      transactions: :timer.minutes(5),
      statistics: :timer.hours(1),
      credentials: :timer.seconds(30),
      balances: :timer.minutes(1),
      users: :timer.minutes(10)
    }
  ],
  
  # Retry Configuration
  retry: [
    enabled: true,
    max_attempts: 3,
    backoff_multiplier: 2,
    initial_delay: 1_000,
    max_delay: 10_000,
    # HTTP status codes to retry
    retry_on_status: [429, 500, 502, 503, 504],
    # Error types to retry
    retry_on_errors: [:timeout, :network_error, :connection_closed]
  ],
  
  # Debug mode
  debug_mode: false

# =============================================================================
# Finch HTTP Client Pool Configuration
# =============================================================================

config :tink_ex, TinkEx.Finch,
  pools: %{
    default: [
      size: 32,
      count: 1,
      # Connection settings
      conn_opts: [
        timeout: 30_000,
        # TLS/SSL settings
        transport_opts: [
          verify: :verify_peer,
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      ],
      # Pool settings
      pool_opts: [
        max_idle_time: :timer.seconds(30),
        protocol: :http1
      ]
    ]
  }

# =============================================================================
# Telemetry & Logging
# =============================================================================

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :module, :function]

# Configure telemetry events
config :tink_ex, :telemetry,
  events: [
    [:tink_ex, :request, :start],
    [:tink_ex, :request, :stop],
    [:tink_ex, :request, :exception],
    [:tink_ex, :cache, :hit],
    [:tink_ex, :cache, :miss]
  ]

# =============================================================================
# OAuth & JWT (optional)
# =============================================================================

# OAuth2 client configuration (if using oauth2 library)
config :oauth2,
  serializers: %{
    "application/json" => Jason
  }

# Joken JWT configuration (if using joken library)
config :joken,
  default_signer: nil  # Set in runtime.exs from env vars

# =============================================================================
# Import Environment-Specific Configuration
# =============================================================================

# Import environment-specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
