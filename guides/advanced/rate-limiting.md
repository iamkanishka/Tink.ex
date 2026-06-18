# Rate Limiting

`Tink.ex` includes client-side rate limiting via [Hammer](https://hex.pm/packages/hammer)
to prevent hitting Tink's server-side 429 limits before they happen.

## Configuration

```elixir
config :tink,
  rate_limit: [
    enabled:          true,
    requests_per_min: 600,   # Tink's default limit per client_id
    burst_size:       60     # max burst above the per-minute rate
  ]
```

Disable rate limiting (e.g. in tests):

```elixir
# config/test.exs
config :tink,
  rate_limit: [enabled: false]
```

## How it works

Rate limiting uses a token bucket algorithm. The bucket is keyed by `client_id`
so multiple processes in your application share the same counter. Checks are
performed in `Tink.Client` before each outbound request.

When the limit is exceeded the call returns immediately with:

```elixir
{:error, %Tink.Error{status: 429, code: "CLIENT_RATE_LIMITED",
                      message: "Client-side rate limit exceeded"}}
```

Note this is a **local** rejection — no request was sent to Tink.

## Manual check

```elixir
case Tink.RateLimiter.check(Tink.Config.client_id()) do
  :ok ->
    # proceed
  {:error, :rate_limited, retry_after_ms} ->
    Process.sleep(retry_after_ms)
end
```

## Telemetry

```elixir
:telemetry.attach("tink-rate-limit", [:tink, :rate_limit, :check],
  fn _event, _measurements, %{key: key, allowed: allowed}, _config ->
    unless allowed do
      Logger.warning("Rate limit hit for key: #{key}")
    end
  end, nil)
```

## Tink's server-side limits

If you exceed Tink's limits, the API returns a `429` status. The client will
automatically retry up to `max_retries` times with jittered exponential backoff
(configurable via `retry_delay`). See the [Error Handling guide](error-handling.md)
for retry configuration.
