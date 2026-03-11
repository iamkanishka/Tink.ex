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
  ],
  rate_limit: [
    enabled: false,
    max_requests: 0,
    interval: 0,
    strategy: :stop_and_wait
  ]

# =============================================================================
# Test HTTP Pool
# =============================================================================

config :tink, Tink.Finch,
  pools: %{
    default: [
      size: 2,
      count: 1,
      conn_opts: [
        timeout: 5_000
      ],
      pool_opts: [
        max_idle_time: :timer.seconds(5),
        protocol: :http1
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
# Test Mocking
# =============================================================================

config :tink, :mox, verify_on_exit: true

config :bypass,
  enable_debug_log: false

# =============================================================================
# Test Coverage
# =============================================================================

config :excoveralls,
  test_coverage: [
    tool: ExCoveralls,
    summary: true,
    print_summary: true
  ]

config :excoveralls, :exclude,
  test: true,
  ignored_modules: [
    Tink.MockHTTPAdapter
  ]

# =============================================================================
# Async Testing
# =============================================================================

config :tink, :test,
  async: true,
  max_cases: System.schedulers_online() * 2

# =============================================================================
# Test Database (uncomment if using Ecto)
# =============================================================================

# config :tink, Tink.Repo,
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   database: "tink_test#{System.get_env("MIX_TEST_PARTITION")}",
#   pool: Ecto.Adapters.SQL.Sandbox,
#   pool_size: 10
