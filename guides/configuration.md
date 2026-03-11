# Configuration

Tink is configured via the standard `config :tink` namespace.
All options can be set in `config/runtime.exs` for twelve-factor compatibility.

## Required Options

```elixir
config :tink,
  client_id:     System.get_env("TINK_CLIENT_ID"),
  client_secret: System.get_env("TINK_CLIENT_SECRET")
```

## Full Reference

```elixir
config :tink,
  # --- Credentials (required) ---
  client_id:     System.get_env("TINK_CLIENT_ID"),
  client_secret: System.get_env("TINK_CLIENT_SECRET"),

  # --- API ---
  base_url: "https://api.tink.com",   # default; change for sandbox
  timeout:  30_000,                    # HTTP timeout in ms (default: 30s)

  # --- Connection pool ---
  pool_size: 32,         # Finch connection pool size (default: 32 in prod, 2 in test)

  # --- Retries ---
  max_retries:   3,      # Maximum retry attempts (default: 3)
  retry_delay:   500,    # Base delay between retries in ms (default: 500)

  # --- Rate limiting (requires :hammer dep) ---
  enable_rate_limiting: true,

  # --- Cache (requires :cachex dep) ---
  cache: [
    enabled:  true,
    max_size: 1_000     # Maximum number of cached entries
  ],

  # --- Debug ---
  debug_mode: false     # Logs all HTTP requests/responses when true
```

## Rate Limiter Tuning

```elixir
# Tune the cleanup GenServer interval (default: 5 minutes)
config :tink, Tink.RateLimiter.Backend,
  clean_period: :timer.minutes(5)
```

## Environment-Specific Configuration

```elixir
# config/dev.exs
config :tink,
  base_url:   "https://api.tink.com",
  debug_mode: true

# config/test.exs
config :tink,
  enable_rate_limiting: false,
  cache: [enabled: false]

# config/runtime.exs  (production — twelve-factor)
if config_env() == :prod do
  config :tink,
    client_id:     System.fetch_env!("TINK_CLIENT_ID"),
    client_secret: System.fetch_env!("TINK_CLIENT_SECRET")
end
```

## Per-Request Options

Options can also be overridden on individual client structs:

```elixir
{:ok, client} = Tink.Client.new(
  client_id:     "...",
  client_secret: "...",
  timeout:       60_000,
  cache:         false
)
```
