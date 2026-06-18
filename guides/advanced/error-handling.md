# Error Handling

All `Tink.ex` functions return `{:ok, map()}` or `{:error, %Tink.Error{}}`.
Errors are never raised — the caller always pattern-matches the result.

## The `Tink.Error` struct

```elixir
%Tink.Error{
  status:     404,
  code:       "NOT_FOUND",
  message:    "Account not found",
  request_id: "req-abc123",   # from X-Tink-Request-Id header — useful for Tink support
  details:    %{...}          # raw response body
}
```

## Pattern matching

```elixir
case Tink.Accounts.get(client, account_id) do
  {:ok, account} ->
    # happy path
    IO.inspect(account["id"])

  {:error, %Tink.Error{status: 401}} ->
    # token expired — refresh and retry
    {:ok, new_client} = Tink.Auth.refresh(client, refresh_token)
    Tink.Accounts.get(new_client, account_id)

  {:error, %Tink.Error{status: 404}} ->
    # resource not found — handle gracefully
    nil

  {:error, %Tink.Error{status: 429, request_id: rid}} ->
    # rate limited — log and back off
    Logger.warning("Rate limited, request_id=#{rid}")
    :rate_limited

  {:error, %Tink.Error{status: nil, code: "NETWORK_ERROR"}} ->
    # network failure — retry or fail gracefully
    :unavailable

  {:error, %Tink.Error{} = err} ->
    # catch-all
    Logger.error(Exception.message(err))
    {:error, err}
end
```

## Retryable vs non-retryable errors

The client automatically retries on `429` and `503` and network failures using
full-jitter exponential backoff. These status codes are **never** retried:

| Status | Meaning | Retry? |
|--------|---------|--------|
| 400 | Bad request | ✗ |
| 401 | Unauthorized / token expired | ✗ |
| 403 | Forbidden / missing scope | ✗ |
| 404 | Resource not found | ✗ |
| 422 | Unprocessable entity | ✗ |
| 429 | Rate limited | ✓ (up to `max_retries`) |
| 503 | Service unavailable | ✓ |
| `nil` | Network error | ✓ |

## Retry configuration

```elixir
config :tink,
  max_retries: 3,     # default 3 — set to 0 to disable
  retry_delay: 500    # base delay ms; actual delay is jittered exponentially
```

Per-call override:

```elixir
Tink.Accounts.list(client, max_retries: 0)  # disable retry for this call
```

## Timeout errors

Timeouts surface as `%Tink.Error{status: nil, code: "NETWORK_ERROR"}`.
Configure the timeout:

```elixir
config :tink, timeout: 30_000   # ms, default 30s
```

## Polling timeouts

Polling helpers (`poll_until_terminal`, `poll_until_complete`, `poll_operation`)
return `{:error, :timeout}` — an atom, not a `%Tink.Error{}` — when the deadline
is exceeded:

```elixir
case Tink.Payments.poll_until_terminal(client, payment_id, timeout_ms: 30_000) do
  {:ok, %{"status" => "SUCCESSFUL"}} -> :paid
  {:ok, %{"status" => "FAILED"}}     -> :failed
  {:error, :timeout}                 -> :timed_out
  {:error, %Tink.Error{} = err}      -> {:error, err}
end
```

## Request IDs for support

Every API error includes a `request_id` (from the `X-Tink-Request-Id` response
header). Always log this when reporting issues to Tink support:

```elixir
case result do
  {:error, %Tink.Error{request_id: rid} = err} when not is_nil(rid) ->
    Logger.error("Tink API error. request_id=#{rid} — #{Exception.message(err)}")
  {:error, err} ->
    Logger.error("Tink API error: #{inspect(err)}")
end
```
