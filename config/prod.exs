import Config

# =============================================================================
# Production Environment Configuration
# =============================================================================

# NOTE: This file is loaded at compile time.
# Runtime configuration (API keys, pool sizing, log level) lives in runtime.exs.

config :tink,
  base_url: "https://api.tink.com",
  http_adapter: Tink.HTTPAdapter,

  timeout: 30_000,
  receive_timeout: 30_000,

  debug_mode: false,

  # NOTE: All nested keyword lists must be fully specified here — Elixir's
  # config merges these by replacement, not recursively.

  cache: [
    enabled: true,
    default_ttl: :timer.minutes(5),
    max_size: 5000,
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

  retry: [
    enabled: true,
    max_attempts: 3,
    backoff_multiplier: 2,
    initial_delay: 1_000,
    max_delay: 10_000,
    retry_on_status: [429, 500, 502, 503, 504],
    retry_on_errors: [:timeout, :network_error, :connection_closed]
  ],

  rate_limit: [
    enabled: true,
    max_requests: 100,
    interval: :timer.seconds(60),
    strategy: :stop_and_wait
  ]

# =============================================================================
# Production HTTP Pool
# =============================================================================

# NOTE: `count` is set at runtime via runtime.exs using System.schedulers_online()
# so it reflects the actual production host, not the build machine.
config :tink, Tink.Finch,
  pools: %{
    default: [
      size: 100,
      count: 1,
      conn_opts: [
        timeout: 30_000,
        transport_opts: [
          verify: :verify_peer,
          depth: 3,
          cacerts: :public_key.cacerts_get(),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ],
          versions: [:"tlsv1.2", :"tlsv1.3"]
        ]
      ],
      pool_opts: [
        max_idle_time: :timer.minutes(5),
        protocol: :http2
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

config :tink, :telemetry,
  log_events: false,
  events: [
    [:tink, :request, :stop],
    [:tink, :request, :exception],
    [:tink, :cache, :hit],
    [:tink, :cache, :miss]
  ]

# =============================================================================
# Production Security
# =============================================================================

config :tink, :security,
  force_https: true,
  validate_ssl: true,
  max_request_size: 10_485_760

# =============================================================================
# Production Performance
# =============================================================================

config :tink, :performance,
  pool_connections: true,
  http2: true,
  compress_requests: true,
  compress_responses: true

# =============================================================================
# Production Monitoring (uncomment to enable)
# =============================================================================

# Sentry
# config :sentry,
#   dsn: System.get_env("SENTRY_DSN"),
#   environment_name: :prod,
#   enable_source_code_context: true,
#   root_source_code_path: File.cwd!(),
#   tags: %{env: "production", app: "tink"},
#   included_environments: [:prod]

# AppSignal
# config :appsignal, :config,
#   active: true,
#   name: "Tink",
#   push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY"),
#   env: :prod

# =============================================================================
# Production Database (uncomment if using Ecto)
# =============================================================================

# config :tink, Tink.Repo,
#   pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
#   queue_target: 5_000,
#   queue_interval: 10_000
