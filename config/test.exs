import Config

# =============================================================================
# Test Environment Configuration
# =============================================================================

config :tink,
  base_url: "https://test-api.tink.com",
  client_id: "test_client_id",
  client_secret: "test_client_secret",
  timeout: 5_000,
  receive_timeout: 5_000,
  http_adapter: Tink.MockHTTPAdapter,
  debug_mode: false,
  enable_rate_limiting: false,

  # NOTE: All nested keyword lists must be fully specified here — Elixir's
  # config merges these by replacement, not recursively.

  cache: [
    enabled: false,
    default_ttl: 0,
    max_size: 100,
    ttls: %{
      providers: 0,
      categories: 0,
      accounts: 0,
      transactions: 0,
      statistics: 0,
      credentials: 0,
      balances: 0,
      users: 0
    }
  ],
  retry: [
    enabled: false,
    max_attempts: 1,
    backoff_multiplier: 1,
    initial_delay: 0,
    max_delay: 0,
    retry_on_status: [],
    retry_on_errors: []
  ]

# =============================================================================
# Test HTTP Pool
# =============================================================================

config :tink, Tink.Finch,
  pools: %{
    default: [
      size: 2,
      count: 1,
      max_idle_time: :timer.seconds(5),
      protocol: :http1,
      conn_opts: [
        timeout: 5_000
      ]
    ]
  }

# =============================================================================
# Test Logging
# =============================================================================

config :logger,
  level: :warning,
  backends: [:console]

config :logger, :console,
  format: "[$level] $message\n",
  metadata: []

# =============================================================================
# ExUnit Configuration
# =============================================================================

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 500,
  refute_receive_timeout: 100

# =============================================================================
# Test Telemetry
# =============================================================================

config :tink, :telemetry,
  log_events: false,
  events: []

# =============================================================================
# Test OAuth/JWT
# =============================================================================

config :joken,
  default_signer: [
    signer_alg: "HS256",
    key_pem: "test-secret-key-not-for-production"
  ]

# =============================================================================
# Test Tooling
# =============================================================================

config :tink, :mox, verify_on_exit: true

config :bypass, enable_debug_log: false

config :excoveralls,
  test_coverage: [
    tool: ExCoveralls,
    summary: true,
    print_summary: true
  ],
  ignore_modules: [Tink.MockHTTPAdapter]
