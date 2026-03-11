# Getting Started

Tink is a production-ready Elixir client for the [Tink open banking API](https://docs.tink.com).
It provides access to account aggregation, transaction data, financial insights,
and verification services across hundreds of European banks.

## Installation

Add `tink` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:tink, "~> 0.1"},

    # Optional: caching support
    {:cachex, "~> 4.1"},

    # Optional: rate limiting
    {:hammer, "~> 7.2"}
  ]
end
```

Run `mix deps.get` to fetch dependencies.

## Tink Account Setup

Before making API calls you need a Tink developer account:

1. Sign up at [console.tink.com](https://console.tink.com)
2. Create an app to obtain a **Client ID** and **Client Secret**
3. Configure your redirect URI and enabled scopes

## Minimal Configuration

Add to `config/runtime.exs`:

```elixir
config :tink,
  client_id: System.get_env("TINK_CLIENT_ID"),
  client_secret: System.get_env("TINK_CLIENT_SECRET")
```

Set the environment variables before starting your application:

```sh
export TINK_CLIENT_ID="your_client_id"
export TINK_CLIENT_SECRET="your_client_secret"
```

## Your First API Call

```elixir
# 1. Build a client with client credentials
{:ok, client} = Tink.Client.new(
  client_id: "your_client_id",
  client_secret: "your_client_secret"
)

# 2. Authenticate with the Tink API
{:ok, token} = Tink.Auth.client_credentials(client, scope: "user:read")

# 3. Attach the token to the client
authenticated_client = Tink.Client.with_token(client, token)

# 4. Make an API call
{:ok, users} = Tink.Users.list(authenticated_client)
```

## Error Handling

All Tink functions return tagged tuples:

```elixir
case Tink.Accounts.list(client) do
  {:ok, accounts} ->
    Enum.each(accounts, &IO.inspect/1)

  {:error, %Tink.Error{status: 401}} ->
    Logger.error("Authentication failed — token may have expired")

  {:error, %Tink.Error{status: 429}} ->
    Logger.warning("Rate limit exceeded — backing off")

  {:error, %Tink.Error{} = err} ->
    Logger.error("API error: #{err.message}")
end
```

## Next Steps

- [Authentication](authentication.md) — token flows, refresh, and scopes
- [Configuration](configuration.md) — all available options
- [Error Handling](advanced/error-handling.md) — retries and error types
