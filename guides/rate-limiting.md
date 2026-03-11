# Rate Limiting

Tink includes built-in rate limiting via `Tink.RateLimiter` to help you
stay within Tink's API quotas and avoid 429 responses.

## Requirements

Rate limiting requires the `:hammer` optional dependency:

```elixir
# mix.exs
{:hammer, "~> 7.2"}
```

## How It Works

`Tink.RateLimiter` uses Hammer 7.2's fixed-window ETS algorithm via a
private `Tink.RateLimiter.Backend` module. The backend is supervised by
`Tink.Application` and starts automatically when rate limiting is enabled.

Each request key maps to a sliding counter in an ETS table. When the count
exceeds the limit for the current window, `check/2` returns
`{:error, :rate_limited}`.

## Enabling Rate Limiting

```elixir
# config/config.exs
config :tink,
  enable_rate_limiting: true
```

## Default Limits

Tink applies a default limit of **100 requests per hour** per key, matching
Tink's standard per-user quota.

## Checking Limits Manually

```elixir
case Tink.RateLimiter.check("user_#{user_id}") do
  :ok ->
    make_api_call()

  {:error, :rate_limited} ->
    {:error, "Rate limit reached — please try again later"}
end
```

## Custom Limits Per Operation

Some Tink endpoints have tighter limits. Override per call:

```elixir
# 10 requests per minute for a heavy endpoint
Tink.RateLimiter.check("bulk_fetch:#{user_id}",
  limit:  10,
  period: :timer.minutes(1)
)
```

## Inspecting Remaining Quota

```elixir
{:ok, remaining} = Tink.RateLimiter.remaining("user_#{user_id}")
# Returns the number of requests left in the current window
```

## Detailed Info

```elixir
{:ok, info} = Tink.RateLimiter.info("user_#{user_id}")
# %{count: 42, limit: 100, remaining: 58}
```

## Tuning the Cleanup Interval

The ETS backend runs a periodic cleanup to remove expired window entries.
Configure the interval (default: every 5 minutes):

```elixir
config :tink, Tink.RateLimiter.Backend,
  clean_period: :timer.minutes(10)
```

## Disabling in Tests

```elixir
# config/test.exs
config :tink,
  enable_rate_limiting: false
```

## Tink Rate Limit Reference

| Endpoint type | Limit |
|---|---|
| Most user-scoped endpoints | 100 req/hour/user |
| Public / metadata endpoints | Higher (varies) |
| Webhook delivery | N/A (push-based) |

When a 429 is received, Tink's `Tink.Retry` module will automatically
back off and retry up to `max_retries` times before surfacing the error.
