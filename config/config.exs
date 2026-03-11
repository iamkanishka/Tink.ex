import Config

# =============================================================================
# Tink Core Configuration
# =============================================================================

config :tink,
  base_url: "https://api.tink.com",
  http_adapter: Tink.HTTPAdapter,
  timeout: 30_000,
  receive_timeout: 30_000,

  rate_limit: [
    enabled: false,
    max_requests: 100,
    interval: :timer.seconds(60),
    strategy: :stop_and_wait
  ],

  cache: [
    enabled: true,
    default_ttl: :timer.minutes(5),
    max_size: 1000,
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

  retry: [
    enabled: true,
    max_attempts: 3,
    backoff_multiplier: 2,
    initial_delay: 1_000,
    max_delay: 10_000,
    retry_on_status: [429, 500, 502, 503, 504],
    retry_on_errors: [:timeout, :network_error, :connection_closed]
  ],

  debug_mode: false

# =============================================================================
# Finch HTTP Client Pool Configuration
# =============================================================================

config :tink, Tink.Finch,
  pools: %{
    default: [
      size: 32,
      count: 1,
      conn_opts: [
        timeout: 30_000,
        transport_opts: [
          verify: :verify_peer,
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      ],
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

config :tink, :telemetry,
  events: [
    [:tink, :request, :start],
    [:tink, :request, :stop],
    [:tink, :request, :exception],
    [:tink, :cache, :hit],
    [:tink, :cache, :miss]
  ]

# =============================================================================
# OAuth & JWT
# =============================================================================

config :oauth2,
  serializers: %{
    "application/json" => Jason
  }

# JWT signer is set per-environment in runtime.exs
config :joken,
  default_signer: nil

# =============================================================================
# Hammer Rate Limiter Backend Configuration
# =============================================================================

config :tink, Tink.RateLimiter.Backend,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: :timer.hours(2),
       cleanup_rate_ms: :timer.minutes(10)
     ]}

# =============================================================================
# Import Environment-Specific Configuration
# =============================================================================

import_config "#{config_env()}.exs"
