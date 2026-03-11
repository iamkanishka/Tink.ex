defmodule Tink.Cache do
  @moduledoc """
  Caching layer for Tink API responses.

  This module provides intelligent caching for API responses to reduce API calls,
  improve performance, and stay within rate limits. It uses Cachex for persistent
  caching with configurable TTLs.

  ## Configuration

      config :tink, :cache,
        enabled: true,
        default_ttl: :timer.minutes(5),
        max_size: 1000

  ## Cache TTLs by Resource Type

  - **Providers**: 1 hour (rarely change)
  - **Categories**: 1 day (static reference data)
  - **User Data / Accounts**: 5 minutes
  - **Balances**: 1 minute (frequently updated)
  - **Statistics**: 1 hour (aggregated data)
  - **Credentials**: 30 seconds (status changes frequently)
  - **Reports** (income/expense/risk): 24 hours (immutable once generated)
  """

  require Logger

  @cache_name :tink_cache

  # Default TTLs for different resource types (in milliseconds)
  @default_ttls %{
    providers: :timer.hours(1),
    categories: :timer.hours(24),
    accounts: :timer.minutes(5),
    transactions: :timer.minutes(5),
    statistics: :timer.hours(1),
    credentials: :timer.seconds(30),
    balances: :timer.minutes(1),
    users: :timer.minutes(10),
    # Immutable reports — income check, expense check, risk insights, etc.
    reports: :timer.hours(24),
    default: :timer.minutes(5)
  }

  @doc """
  Gets a value from the cache.

  Returns `{:ok, value}` on hit, `{:error, :not_found}` on miss.
  """
  @spec get(String.t()) :: {:ok, term()} | {:error, term()}
  def get(key) when is_binary(key) do
    if enabled?() do
      case Cachex.get(@cache_name, key) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, value} ->
          Logger.debug("[Tink.Cache] HIT: #{key}")
          {:ok, value}

        {:error, _} = error ->
          error
      end
    else
      {:error, :cache_disabled}
    end
  end

  @doc """
  Puts a value in the cache with optional TTL or resource type.

      :ok = Tink.Cache.put("providers:GB", providers, resource_type: :providers)
      :ok = Tink.Cache.put("custom:key", value, ttl: :timer.minutes(10))
  """
  @spec put(String.t(), term(), keyword()) :: :ok | {:error, term()}
  def put(key, value, opts \\ []) when is_binary(key) do
    if enabled?() do
      ttl = resolve_ttl(opts)

      case Cachex.put(@cache_name, key, value, ttl: ttl) do
        {:ok, true} ->
          Logger.debug("[Tink.Cache] PUT: #{key} (TTL: #{ttl}ms)")
          :ok

        {:error, _} = error ->
          Logger.warning("[Tink.Cache] PUT failed for #{key}: #{inspect(error)}")
          error
      end
    else
      :ok
    end
  end

  @doc """
  Fetches a value from cache, computing it with `fun` on miss.

      {:ok, providers} = Tink.Cache.fetch("providers:GB", fn ->
        call_api()
      end, resource_type: :providers)
  """
  @spec fetch(String.t(), (-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def fetch(key, fun, opts \\ []) when is_binary(key) and is_function(fun, 0) do
    if enabled?() do
      case get(key) do
        {:ok, value} ->
          {:ok, value}

        {:error, :not_found} ->
          Logger.debug("[Tink.Cache] MISS: #{key}")

          case fun.() do
            {:ok, value} = success ->
              put(key, value, opts)
              success

            {:error, _} = error ->
              error
          end

        {:error, _} = error ->
          error
      end
    else
      fun.()
    end
  end

  @doc """
  Deletes a value from the cache.
  """
  @spec delete(String.t()) :: :ok | {:error, boolean()}
  def delete(key) when is_binary(key) do
    if enabled?() do
      case Cachex.del(@cache_name, key) do
        {:ok, _} ->
          Logger.debug("[Tink.Cache] DELETE: #{key}")
          :ok

        {:error, _} = error ->
          error
      end
    else
      :ok
    end
  end

  @doc """
  Clears all cached values.
  """
  @spec clear() :: :ok | {:error, integer()}
  def clear do
    if enabled?() do
      case Cachex.clear(@cache_name) do
        {:ok, _} ->
          Logger.info("[Tink.Cache] Cache cleared")
          :ok

        {:error, _} = error ->
          error
      end
    else
      :ok
    end
  end

  @doc """
  Returns cache statistics, or `nil` if cache is disabled.

      %{hit_rate: 0.75, hits: 150, misses: 50, size: 45} = Tink.Cache.stats()
  """
  @spec stats() :: %{hit_rate: float(), hits: term(), misses: term(), size: term()} | nil
  def stats do
    if enabled?() do
      case Cachex.stats(@cache_name) do
        {:ok, raw_stats} ->
          # Cachex.stats/1 returns a struct-like map; use Map.get for safety
          get_count = Map.get(raw_stats, :get_count, 0)
          hit_count = Map.get(raw_stats, :hit_count, 0)
          miss_count = Map.get(raw_stats, :miss_count, 0)

          hit_rate =
            if get_count > 0 do
              Float.round(hit_count / get_count, 2)
            else
              0.0
            end

          %{
            hit_rate: hit_rate,
            hits: hit_count,
            misses: miss_count,
            size: Cachex.size!(@cache_name)
          }

        {:error, _} ->
          nil
      end
    else
      nil
    end
  end

  @doc """
  Builds a cache key from a list of components joined by `:`.

      "providers:GB" = Tink.Cache.build_key(["providers", "GB"])
  """
  @spec build_key([String.t() | atom()]) :: String.t()
  def build_key(components) when is_list(components) do
    components
    |> Enum.map(&to_string/1)
    |> Enum.join(":")
  end

  @doc """
  Invalidates all cache entries belonging to a user.

  Uses a `Stream` over Cachex keys to avoid loading all keys into memory at
  once, making it efficient even for large caches.

  All user keys are stored under the `"<user_id>:"` prefix, so prefix matching
  is exact and cannot collide with a shorter user ID like `"user_1"` matching
  `"user_10:..."`.
  """
  @spec invalidate_user(String.t()) :: :ok
  def invalidate_user(user_id) when is_binary(user_id) do
    if enabled?() do
      prefix = "#{user_id}:"

      case Cachex.keys(@cache_name) do
        {:ok, keys} ->
          keys
          |> Stream.filter(&String.starts_with?(&1, prefix))
          |> Stream.each(&delete/1)
          |> Stream.run()

          Logger.debug("[Tink.Cache] Invalidated cache for user: #{user_id}")
          :ok

        {:error, _} ->
          :ok
      end
    else
      :ok
    end
  end

  @doc """
  Checks if caching is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    case Application.get_env(:tink, :cache) do
      nil -> true
      config -> Keyword.get(config, :enabled, true)
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp resolve_ttl(opts) do
    cond do
      Keyword.has_key?(opts, :ttl) ->
        Keyword.get(opts, :ttl)

      Keyword.has_key?(opts, :resource_type) ->
        resource_type = Keyword.get(opts, :resource_type)
        Map.get(@default_ttls, resource_type, @default_ttls.default)

      true ->
        config = Application.get_env(:tink, :cache, [])
        Keyword.get(config, :default_ttl, @default_ttls.default)
    end
  end
end
