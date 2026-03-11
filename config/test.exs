import Config

# =============================================================================
# Test Environment Configuration
# =============================================================================

# Configure TinkEx for testing
config :tink_ex,
  # Use test/mock API endpoint
  base_url: "https://test-api.tink.com",
  
  # Test credentials (can be fake for testing with mocks)
  client_id: "test_client_id",
  client_secret: "test_client_secret",
  
  # Shorter timeouts for faster test execution
  timeout: 5_000,
  receive_timeout: 5_000,
  
  # Use mock HTTP adapter in tests
  http_adapter: TinkEx.MockHTTPAdapter,
  
  # Disable caching in tests for predictable behavior
  cache: [
    enabled: false,
    default_ttl: 0,
    max_size: 0
  ],
  
  # Disable retries in tests for faster failures
  retry: [
    enabled: false,
    max_attempts: 1
  ],
  
  # Disable rate limiting in tests
  rate_limit: [
    enabled: false
  ],
  
  # Enable debug in tests
  debug_mode: false

# =============================================================================
# Test HTTP Pool - Minimal for tests
# =============================================================================

config :tink_ex, TinkEx.Finch,
  pools: %{
    default: [
      size: 2,
      count: 1,
      conn_opts: [
        timeout: 5_000
      ]
    ]
  }

# =============================================================================
# Test Logging - Minimal
# =============================================================================

# Only log warnings and errors in test environment
config :logger,
  level: :warning,
  backends: [:console]

config :logger, :console,
  format: "[$level] $message\n",
  metadata: []

# =============================================================================
# ExUnit Configuration
# =============================================================================

# Configure ExUnit
config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 500,
  refute_receive_timeout: 100

# =============================================================================
# Test Database (if using Ecto)
# =============================================================================

# Uncomment if using database for testing
# config :tink_ex, TinkEx.Repo,
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   database: "tink_ex_test#{System.get_env("MIX_TEST_PARTITION")}",
#   pool: Ecto.Adapters.SQL.Sandbox,
#   pool_size: 10

# =============================================================================
# Test Mocking
# =============================================================================

# Configure Mox for mocking
config :tink_ex, :mox,
  # Verify mocks on exit
  verify_on_exit: true

# =============================================================================
# Test Bypass (for HTTP mocking)
# =============================================================================

# Bypass will start on a random port
config :bypass,
  # Don't print bypass info in tests
  enable_debug_log: false

# =============================================================================
# Test Coverage
# =============================================================================

# ExCoveralls configuration
config :excoveralls,
  test_coverage: [
    tool: ExCoveralls,
    summary: true,
    print_summary: true
  ]

# Coverage options
config :excoveralls, :exclude,
  test: true,
  ignored_modules: [
    TinkEx.MockHTTPAdapter
  ]

# =============================================================================
# Test Telemetry - Disabled
# =============================================================================

config :tink_ex, :telemetry,
  # Don't log telemetry events in tests
  log_events: false,
  events: []

# =============================================================================
# Test OAuth/JWT
# =============================================================================

# Use test/fake keys
config :joken,
  default_signer: [
    signer_alg: "HS256",
    key_pem: "test-secret-key-not-for-production"
  ]

# =============================================================================
# Async Testing
# =============================================================================

# Configure for async tests
config :tink_ex, :test,
  async: true,
  # Maximum number of async test processes
  max_cases: System.schedulers_online() * 2
