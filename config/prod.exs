import Config

# =============================================================================
# Production Environment Configuration
# =============================================================================
# This file is loaded at compile time.
# Runtime configuration (credentials, pool sizing, log level) lives in runtime.exs.

config :tink,
  base_url: "https://api.tink.com",
  http_adapter: Tink.HTTPAdapter,
  timeout: 30_000,
  receive_timeout: 30_000,
  debug_mode: false,
  enable_rate_limiting: true,

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
  ]

# =============================================================================
# Production HTTP Pool
# =============================================================================
# transport_opts with cacerts and pkix_verify_hostname_match_fun/1 cannot be set
# here at compile time because pkix_verify_hostname_match_fun returns a closure.
# The full prod pool config (including transport_opts) is set in runtime.exs.
#
# count is also deferred to runtime.exs so it reflects the actual production
# host's scheduler count rather than the build machine's.

config :tink, Tink.Finch,
  pools: %{
    default: [
      size: 100,
      count: 1,
      max_idle_time: :timer.minutes(5),
      protocol: :http2,
      conn_opts: [
        timeout: 30_000
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
