import Config

# =============================================================================
# Development Environment Configuration
# =============================================================================

config :tink,
  base_url: System.get_env("TINK_API_URL", "https://api.tink.com"),
  timeout: 15_000,
  receive_timeout: 15_000,
  debug_mode: true,
  enable_rate_limiting: false,

  # NOTE: All nested keyword lists must be fully specified here — Elixir's
  # config merges these by replacement, not recursively.

  cache: [
    enabled: true,
    default_ttl: :timer.minutes(30),
    max_size: 500,
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
  retry: [
    enabled: true,
    max_attempts: 3,
    backoff_multiplier: 2,
    initial_delay: 500,
    max_delay: 5_000,
    retry_on_status: [429, 500, 502, 503, 504],
    retry_on_errors: [:timeout, :network_error, :connection_closed]
  ]

# =============================================================================
# Development HTTP Pool
# =============================================================================

config :tink, Tink.Finch,
  pools: %{
    default: [
      size: 10,
      count: 1,
      max_idle_time: :timer.seconds(30),
      protocol: :http1,
      conn_opts: [
        timeout: 15_000
      ]
    ]
  }

# =============================================================================
# Development Logging
# =============================================================================

config :logger, :console,
  format: "\n$time [$level] $metadata\n$message\n",
  metadata: [:request_id, :module, :function, :file, :line],
  level: :debug

config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :debug]
  ]

# =============================================================================
# Development Telemetry
# =============================================================================

config :tink, :telemetry,
  log_events: true,
  events: [
    [:tink, :request, :start],
    [:tink, :request, :stop],
    [:tink, :request, :exception],
    [:tink, :cache, :hit],
    [:tink, :cache, :miss],
    [:tink, :retry, :attempt]
  ]

# =============================================================================
# Development OAuth/JWT
# =============================================================================

# JWT secret is loaded at runtime from env vars via runtime.exs.
# This is a compile-time fallback for IEx sessions only — never use in staging.
config :joken,
  default_signer: [
    signer_alg: "HS256",
    key_pem: System.get_env("JWT_SECRET", "dev-secret-key-change-in-production")
  ]

# =============================================================================
# IEx Console
# =============================================================================

config :iex,
  inspect: [
    pretty: true,
    limit: :infinity,
    width: 120
  ]
