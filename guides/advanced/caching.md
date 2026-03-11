# Caching

Tink uses `Tink.Cache` (backed by Cachex) to reduce redundant API calls for
data that changes infrequently — providers, categories, account metadata, and
aggregated statistics.

## Requirements

Caching requires the `:cachex` optional dependency:

```elixir
# mix.exs
{:cachex, "~> 4.1"}
```

## Enabling the Cache

```elixir
# config/config.exs
config :tink,
  cache: [
    enabled:  true,
    max_size: 1_000    # maximum number of cached entries
  ]
```

## What Gets Cached

| Module | Function | TTL |
|---|---|---|
| `Tink.Providers` | `list_providers/2`, `get_provider/2` | 1h / 2h |
| `Tink.Categories` | `list_categories/2`, `get_category/3` | 24h |
| `Tink.Accounts` | `list_accounts/2`, `get_account/2` | 5 min |
| `Tink.Accounts` | `get_balances/2` | 1 min |
| `Tink.Statistics` | all `get_*` functions | 1h |
| `Tink.Investments` | `list_accounts/1`, `get_holdings/2` | 5 min |
| `Tink.Loans` | `list_accounts/1`, `get_account/2` | 5 min |
| `Tink.Budgets` | `get_budget/2`, `list_budgets/2` | 5 min |

Write operations (e.g. `update_budget/3`) automatically invalidate the
affected cache entries.

## Cache Keys

Keys follow the pattern `"user_id:resource:identifier"`. The cache is scoped
per user — invalidating a user's cache only affects that user's entries:

```elixir
Tink.Cache.invalidate_user("user_123")
```

## Bypassing the Cache

Pass `cache: false` on any client to skip caching for a specific call:

```elixir
client_no_cache = %{client | cache: false}
{:ok, accounts} = Tink.Accounts.list(client_no_cache)
```

## Manual Cache Control

```elixir
# Check if cache is enabled
Tink.Cache.enabled?()   # true | false

# Store a value manually
Tink.Cache.put("my_key", my_value, ttl: :timer.minutes(10))

# Retrieve a value
Tink.Cache.get("my_key")   # {:ok, value} | {:error, :not_found}

# Delete a specific key
Tink.Cache.delete("my_key")

# Invalidate all entries for a user
Tink.Cache.invalidate_user("user_123")
```

## Disabling in Tests

```elixir
# config/test.exs
config :tink,
  cache: [enabled: false]
```

## Cache Stats (Cachex)

Cachex exposes statistics when needed for debugging:

```elixir
Cachex.stats(:tink_cache)
# %{hits: 1234, misses: 56, evictions: 10, ...}
```
