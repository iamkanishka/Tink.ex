defmodule Tink.Cache do
  @moduledoc """
  Cachex-backed response cache with per-resource TTLs, per-user isolation,
  opt-out support, and automatic invalidation on writes.

  ## Configuration

      config :tink,
        cache: [
          enabled:  true,
          max_size: 1_000
        ]

  ## Disabling in tests

      # config/test.exs
      config :tink, cache: [enabled: false]

  ## Per-call bypass

      client_no_cache = %{client | cache: false}
      {:ok, accounts} = Tink.Accounts.list(client_no_cache)

  ## TTLs by resource type

  | TTL key        | Duration  | Used for                          |
  |----------------|-----------|-----------------------------------|
  | `:categories`  | 24 hours  | Enrichment categories             |
  | `:providers`   | 2 hours   | Provider lists and details        |
  | `:statistics`  | 1 hour    | Statistics query results          |
  | `:default`     | 5 minutes | Accounts, investments, loans, etc |
  | `:balances`    | 1 minute  | Account balances                  |
  | `:credentials` | 30 seconds| Credential status                 |

  ## Cache key pattern

  Keys follow `"user_id:resource:identifier"`. Invalidate a whole user's
  entries with `invalidate_user/1`.
  """

  alias Tink.{Config, Telemetry}

  @cache :tink_cache

  @ttls %{
    categories: :timer.hours(24),
    providers: :timer.hours(2),
    statistics: :timer.hours(1),
    default: :timer.minutes(5),
    balances: :timer.minutes(1),
    credentials: :timer.seconds(30)
  }

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc "Whether caching is enabled per application config."
  @spec enabled?() :: boolean()
  def enabled?, do: Config.cache_enabled?()

  @doc """
  Fetch a value from cache; call `fallback` on miss and populate cache.

  Respects `cache: false` on the caller-supplied `client_cache` flag.
  """
  @spec fetch(String.t(), atom(), boolean(), (-> {:ok, any()} | {:error, any()})) ::
          {:ok, any()} | {:error, any()}
  def fetch(key, ttl_key \\ :default, cache_on \\ true, fallback) do
    if enabled?() and cache_on do
      do_fetch(key, ttl_key, fallback)
    else
      fallback.()
    end
  end

  @doc "Get a cached value directly. Returns `{:ok, value}` or `{:error, :not_found}`."
  @spec get(String.t()) :: {:ok, any()} | {:error, :not_found}
  def get(key) do
    case Cachex.get(@cache, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :not_found}
    end
  end

  @doc "Store a value manually."
  @spec put(String.t(), any(), keyword()) :: :ok
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, ttl(:default))
    Cachex.put(@cache, key, value, ttl: ttl)
    :ok
  end

  @doc "Delete a specific cache key."
  @spec delete(String.t()) :: :ok
  def delete(key) do
    Cachex.del(@cache, key)
    :ok
  end

  @doc "Invalidate all cache entries for a user ID."
  @spec invalidate_user(String.t()) :: :ok
  def invalidate_user(user_id) do
    prefix = "#{user_id}:"
    invalidate_prefix(prefix)
  end

  @doc "Invalidate all entries whose key starts with `prefix`."
  @spec invalidate_prefix(String.t()) :: :ok
  def invalidate_prefix(prefix) do
    # Cachex 4.x stream returns {:entry, key, ...} tuples
    case Cachex.keys(@cache) do
      {:ok, keys} ->
        keys
        |> Enum.filter(&String.starts_with?(to_string(&1), prefix))
        |> Enum.each(&Cachex.del(@cache, &1))

      _ ->
        :ok
    end

    :ok
  end

  @doc "Return raw Cachex stats for debugging."
  @spec stats() :: {:ok, map()} | {:error, map()}
  def stats, do: Cachex.stats(@cache)

  # ── TTL helpers ─────────────────────────────────────────────────────────────

  @doc "Return the TTL in ms for a given TTL key."
  @spec ttl(atom()) :: non_neg_integer()
  def ttl(key), do: Map.get(@ttls, key, @ttls.default)

  # ── Cache key builders ───────────────────────────────────────────────────────

  @doc "Build a scoped cache key: `user_id:resource:extra`."
  @spec key(String.t(), String.t(), String.t() | nil) :: String.t()
  def key(user_id, resource, extra \\ nil) do
    if extra, do: "#{user_id}:#{resource}:#{extra}", else: "#{user_id}:#{resource}"
  end

  @doc "Build a global (non-user-scoped) cache key."
  @spec global_key(String.t(), String.t() | nil) :: String.t()
  def global_key(resource, extra \\ nil) do
    if extra, do: "global:#{resource}:#{extra}", else: "global:#{resource}"
  end

  # ── Internals ────────────────────────────────────────────────────────────────

  defp do_fetch(key, ttl_key, fallback) do
    case Cachex.get(@cache, key) do
      {:ok, nil} ->
        Telemetry.cache_miss(key)

        case fallback.() do
          {:ok, value} = result ->
            Cachex.put(@cache, key, value, ttl: ttl(ttl_key))
            result

          error ->
            error
        end

      {:ok, value} ->
        Telemetry.cache_hit(key)
        {:ok, value}

      {:error, _} ->
        fallback.()
    end
  end
end
