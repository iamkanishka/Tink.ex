# Authentication

Tink uses OAuth 2.0. Tink handles token acquisition, storage, and refresh
through `Tink.Auth` and `Tink.AuthToken`.

## Token Flows

### Client Credentials

Use this flow for server-to-server calls that do not involve an end user:

```elixir
{:ok, token} = Tink.Auth.client_credentials(client,
  scope: "accounts:read,transactions:read"
)
```

### Authorization Code (User OAuth)

For flows that require user consent (e.g. linking a bank account):

```elixir
# 1. Generate the Link URL and redirect the user
{:ok, link} = Tink.Link.create(client,
  user_id: "user_123",
  redirect_uri: "https://yourapp.com/callback",
  scope: "accounts:read,transactions:read"
)

# 2. After the user returns, exchange the code
{:ok, token} = Tink.Auth.exchange_code(client,
  code: params["code"],
  redirect_uri: "https://yourapp.com/callback"
)
```

### Token Refresh

Tokens expire. Refresh before making long-running calls:

```elixir
{:ok, new_token} = Tink.Auth.refresh_token(client, token.refresh_token)
```

Or use the auto-refresh wrapper:

```elixir
{:ok, client} = Tink.Client.with_auto_refresh(client, token)
```

## Token Storage

`Tink.AuthToken` is a plain struct — persist it however suits your app:

```elixir
defmodule MyApp.TokenStore do
  def save(user_id, %Tink.AuthToken{} = token) do
    token
    |> Map.from_struct()
    |> Jason.encode!()
    |> then(&Redix.command(:redix, ["SET", "token:#{user_id}", &1,
                                    "EX", token.expires_in]))
  end

  def load(user_id) do
    case Redix.command(:redix, ["GET", "token:#{user_id}"]) do
      {:ok, nil}  -> {:error, :not_found}
      {:ok, json} -> {:ok, json |> Jason.decode!() |> Tink.AuthToken.from_map()}
    end
  end
end
```

## Scopes

Common scopes used with Tink:

| Scope | Description |
|---|---|
| `accounts:read` | List and read bank accounts |
| `transactions:read` | Read transaction history |
| `user:read` | Read user profile |
| `user:create` | Create Tink users |
| `credentials:read` | Read linked credentials |
| `credentials:write` | Add/update credentials |
| `investments:read` | Read investment accounts |
| `statistics:read` | Read aggregated statistics |

Pass multiple scopes as a comma-separated string:

```elixir
scope: "accounts:read,transactions:read,statistics:read"
```

## Delegated Authentication

When acting on behalf of a specific user, request a user access token:

```elixir
{:ok, user_token} = Tink.Auth.user_access_token(client,
  user_id: "tink_user_id",
  scope: "accounts:read,transactions:read"
)

user_client = Tink.Client.with_token(client, user_token)
{:ok, accounts} = Tink.Accounts.list(user_client)
```
