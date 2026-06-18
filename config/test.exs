import Config

# Test configuration — disables external calls and caching
config :tink,
  client_id: "test_client_id",
  client_secret: "test_client_secret",
  webhook_secret: "test_webhook_secret_32chars_long!",
  http_adapter: Tink.HTTP.Mock,
  max_retries: 0,
  retry_delay: 0,
  cache: [
    # Never cache in tests — ensures clean state per test
    enabled: false
  ],
  rate_limit: [
    # No rate limiting in tests
    enabled: false
  ]
