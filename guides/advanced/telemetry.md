# Telemetry

Tink emits `:telemetry` events for HTTP requests, rate limiting, and cache
operations. Attach handlers to integrate with your observability stack
(StatsD, Prometheus, Datadog, etc.).

## HTTP Request Events

| Event | Measurements | Metadata |
|---|---|---|
| `[:tink, :request, :start]` | `%{system_time: t}` | `%{method:, url:, attempt:}` |
| `[:tink, :request, :stop]` | `%{duration: ms}` | `%{method:, url:, status:, attempt:}` |
| `[:tink, :request, :exception]` | `%{duration: ms}` | `%{method:, url:, kind:, reason:}` |

## Rate Limit Events

| Event | Measurements | Metadata |
|---|---|---|
| `[:tink, :rate_limit, :checked]` | `%{}` | `%{key:, limit:, period_ms:}` |
| `[:tink, :rate_limit, :exceeded]` | `%{}` | `%{key:, limit:, period_ms:}` |

## Cache Events

| Event | Measurements | Metadata |
|---|---|---|
| `[:tink, :cache, :hit]` | `%{}` | `%{key:}` |
| `[:tink, :cache, :miss]` | `%{}` | `%{key:}` |
| `[:tink, :cache, :put]` | `%{}` | `%{key:, ttl_ms:}` |

## Attaching a Handler

```elixir
defmodule MyApp.TinkTelemetry do
  require Logger

  def attach do
    :telemetry.attach_many(
      "my-app-tink-ex",
      [
        [:tink, :request, :stop],
        [:tink, :request, :exception],
        [:tink, :rate_limit, :exceeded],
        [:tink, :cache, :miss]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:tink, :request, :stop], %{duration: duration}, meta, _cfg) do
    Logger.info("[Tink] #{meta.method} #{meta.url} → #{meta.status} in #{duration}ms")
    MyApp.Metrics.histogram("tink.request.duration", duration,
      tags: ["status:#{meta.status}"])
  end

  def handle_event([:tink, :request, :exception], %{duration: duration}, meta, _cfg) do
    Logger.error("[Tink] Request exception: #{meta.kind} #{inspect(meta.reason)}")
    MyApp.Metrics.increment("tink.request.exception")
  end

  def handle_event([:tink, :rate_limit, :exceeded], _measurements, %{key: key}, _cfg) do
    Logger.warning("[Tink] Rate limit exceeded for #{key}")
    MyApp.Metrics.increment("tink.rate_limit.exceeded", tags: ["key:#{key}"])
  end

  def handle_event([:tink, :cache, :miss], _measurements, %{key: key}, _cfg) do
    MyApp.Metrics.increment("tink.cache.miss")
  end
end
```

Attach at application start:

```elixir
# In your Application.start/2
MyApp.TinkTelemetry.attach()
```

## Prometheus via TelemetryMetrics

```elixir
# In your Telemetry supervisor
def metrics do
  [
    Telemetry.Metrics.distribution("tink.request.duration",
      event_name: [:tink, :request, :stop],
      measurement:  :duration,
      tags:         [:status]
    ),
    Telemetry.Metrics.counter("tink.rate_limit.exceeded.count",
      event_name: [:tink, :rate_limit, :exceeded]
    ),
    Telemetry.Metrics.counter("tink.cache.miss.count",
      event_name: [:tink, :cache, :miss]
    )
  ]
end
```
