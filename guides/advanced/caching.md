# Caching

`Tink.ex` uses [Cachex](https://hex.pm/packages/cachex) (v4.1+) for transparent
response caching. Caching is **on by default** and dramatically reduces API calls
for slow-changing resources.

## Configuration

```elixir
# config/config.exs
config :tink,
  cache: [
    enabled:  true,     # Set to false to disable globally
    max_size: 1_000     # Max number of entries in the cache
  ]
```

## Disabling in tests

```elixir
# config/test.exs
config :tink,
  cache: [enabled: false]
```

## Bypassing per-client

Set `cache: false` on a client to skip caching for all calls on that client:

```elixir
client_no_cache = %{user_client | cache: false}
{:ok, accounts} = Tink.Accounts.list(client_no_cache)
```

## TTLs by resource type

| TTL key        | Duration   | Used for                              |
|----------------|------------|---------------------------------------|
| `:categories`  | 24 hours   | Enrichment PFM categories             |
| `:providers`   | 2 hours    | Provider lists and details            |
| `:statistics`  | 1 hour     | Statistics query results              |
| `:default`     | 5 minutes  | Accounts, investments, loans, budgets |
| `:balances`    | 1 minute   | Account balances                      |
| `:credentials` | 30 seconds | Credential status                     |

## Cache key pattern

Keys follow `"token_prefix:resource:identifier"`:

- `"abc12345:accounts:123"` — single account for a user
- `"abc12345:budgets"` — budget list for a user
- `"global:categories:en_US"` — categories (not user-scoped)
- `"global:providers:GB"` — providers for a market

The `token_prefix` is the first 12 characters of the access token. This scopes
entries per user session without storing PII as cache keys.

## Write invalidation

All write operations automatically invalidate the relevant cache entries:

```elixir
# This invalidates both the individual account cache and the list cache
{:ok, updated} = Tink.Accounts.update(client, account_id, %{"name" => "New name"})

# Budget deletion invalidates both the specific budget and the list
:ok = Tink.Budgets.delete(client, budget_id)
```

## Manual invalidation

```elixir
# Delete a specific key
Tink.Cache.delete("abc12345:accounts:account-001")

# Invalidate all entries for a user (e.g. after full refresh)
Tink.Cache.invalidate_user("abc12345")

# Invalidate by prefix
Tink.Cache.invalidate_prefix("abc12345:budgets")

# Check stats
{:ok, stats} = Tink.Cache.stats()
```

## Telemetry

Cache events:

| Event | Metadata |
|---|---|
| `[:tink, :cache, :hit]` | `%{key: cache_key}` |
| `[:tink, :cache, :miss]` | `%{key: cache_key}` |

```elixir
:telemetry.attach("tink-cache", [:tink, :cache, :miss], fn _event, _measurements, meta, _config ->
  Logger.debug("Cache miss: #{meta.key}")
end, nil)
```
