import Config

# Default SDK configuration.
# Override in config/runtime.exs with System.get_env/1 for secrets.

config :tink,
  base_url: "https://api.tink.com",
  link_base_url: "https://link.tink.com",
  timeout: 30_000,
  max_retries: 3,
  retry_delay: 500,
  http_adapter: Tink.HTTP.Finch,
  cache: [
    enabled: true,
    max_size: 1_000
  ],
  rate_limit: [
    enabled: true,
    requests_per_min: 600,
    burst_size: 60
  ]

# Hammer's `Hammer.check_rate/3` (used by Tink.RateLimiter) reads its backend
# from this application config. This MUST be kept in sync with the
# Hammer.Backend.ETS child spec started in Tink.Application.
config :hammer,
  backend:
    {Hammer.Backend.ETS, [expiry_ms: :timer.hours(2), cleanup_interval_ms: :timer.minutes(10)]}

import_config "#{config_env()}.exs"
