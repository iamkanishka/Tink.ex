# Error Handling

All Tink functions return `{:ok, result}` or `{:error, %Tink.Error{}}`.
No exceptions are raised for API-level errors.

## The Error Struct

```elixir
%Tink.Error{
  status:  404,                      # HTTP status code
  code:    "NOT_FOUND",              # Tink error code
  message: "Resource not found",     # Human-readable description
  request_id: "req_abc123"           # Tink request ID for support
}
```

## Pattern Matching on Errors

```elixir
case Tink.Accounts.list(client) do
  {:ok, accounts} ->
    process(accounts)

  {:error, %Tink.Error{status: 401}} ->
    {:error, :unauthenticated}

  {:error, %Tink.Error{status: 403}} ->
    {:error, :forbidden}

  {:error, %Tink.Error{status: 404}} ->
    {:error, :not_found}

  {:error, %Tink.Error{status: 429, message: msg}} ->
    Logger.warning("Rate limited: #{msg}")
    {:error, :rate_limited}

  {:error, %Tink.Error{status: status}} when status >= 500 ->
    {:error, :server_error}

  {:error, %Tink.Error{} = err} ->
    Logger.error("Unexpected error: #{inspect(err)}")
    {:error, :unknown}
end
```

## Automatic Retries

Tink retries transient failures (429, 503, network timeouts) automatically
using exponential backoff with jitter. Configure via:

```elixir
config :tink,
  max_retries: 3,
  retry_delay: 500    # base delay in ms
```

Retry behaviour is handled by `Tink.Retry`. Calls that succeed on a retry
return `{:ok, result}` transparently — retries are invisible to the caller.

## Non-Retryable Errors

The following are never retried:

- `400 Bad Request` — fix the request parameters
- `401 Unauthorized` — refresh the token
- `403 Forbidden` — check scopes
- `404 Not Found` — the resource does not exist
- `422 Unprocessable Entity` — semantic validation error

## Logging Request IDs

Always log the `request_id` when reporting errors to Tink support:

```elixir
case Tink.Transactions.list(client, account_id: id) do
  {:error, %Tink.Error{request_id: rid} = err} ->
    Logger.error("Tink error [request_id=#{rid}]: #{err.message}")
    {:error, :api_error}

  {:ok, _} = ok -> ok
end
```

## Error Codes Reference

| Code | Status | Meaning |
|---|---|---|
| `INVALID_TOKEN` | 401 | Access token is expired or invalid |
| `INSUFFICIENT_SCOPE` | 403 | Token lacks required scope |
| `NOT_FOUND` | 404 | Resource does not exist |
| `RATE_LIMITED` | 429 | Too many requests |
| `TEMPORARY_UNAVAILABLE` | 503 | Tink or bank is temporarily down |
| `PROVIDER_ERROR` | 502 | The connected bank returned an error |
