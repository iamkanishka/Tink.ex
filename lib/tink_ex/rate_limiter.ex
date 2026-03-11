defmodule TinkEx.RateLimiter do
  @moduledoc """
  Rate limiting for TinkEx API requests.

  Implements token bucket algorithm using Hammer for distributed rate limiting.

  ## Tink API Rate Limits

  Different endpoints have different rate limits:
  - Most endpoints: 100 requests per hour per user
  - Some public endpoints: Higher limits
  - Burst allowance: Small bursts allowed

  ## Configuration

      config :tink_ex,
        enable_rate_limiting: true,
        rate_limit_requests: 100,
        rate_limit_period: :timer.hours(1)

  ## Examples

      # Check rate limit before making request
      case TinkEx.RateLimiter.check("user_123") do
        :ok ->
          make_api_request()

        {:error, :rate_limited} ->
          {:error, "Too many requests"}
      end

      # With custom bucket
      TinkEx.RateLimiter.check("operation:fetch_accounts", user_id)

  ## Telemetry

  Emits:
  - `[:tink_ex, :rate_limit, :checked]` - Rate limit check performed
  - `[:tink_ex, :rate_limit, :exceeded]` - Rate limit exceeded
  """

  require Logger

  alias TinkEx.Config

  @default_requests_per_hour 100
  @default_period :timer.hours(1)

  @doc """
  Checks if a request is allowed under rate limits.

  ## Parameters

    * `key` - Rate limit bucket key (e.g., user_id, operation name)
    * `opts` - Options:
      * `:limit` - Maximum requests (default: 100)
      * `:period` - Time period in ms (default: 1 hour)

  ## Returns

    * `:ok` - Request is allowed
    * `{:error, :rate_limited}` - Rate limit exceeded

  ## Examples

      iex> TinkEx.RateLimiter.check("user_123")
      :ok

      iex> TinkEx.RateLimiter.check("user_123", limit: 50, period: :timer.minutes(30))
      :ok
  """
  @spec check(String.t(), keyword()) :: :ok | {:error, :rate_limited}
  def check(key, opts \\ []) do
    if Config.rate_limiting_enabled?() do
      do_check(key, opts)
    else
      :ok
    end
  end

  @doc """
  Gets remaining requests for a given key.

  ## Examples

      iex> TinkEx.RateLimiter.remaining("user_123")
      {:ok, 95}

      iex> TinkEx.RateLimiter.remaining("unknown_key")
      {:ok, 100}
  """
  @spec remaining(String.t(), keyword()) :: {:ok, non_neg_integer()}
  def remaining(key, opts \\ []) do
    if Config.rate_limiting_enabled?() do
      limit = Keyword.get(opts, :limit, @default_requests_per_hour)
      period_ms = Keyword.get(opts, :period, @default_period)

      bucket_key = build_bucket_key(key)

      case Hammer.inspect_bucket(bucket_key, period_ms, limit) do
        {:ok, {_count, count_remaining, _ms_to_next_bucket, _created_at, _updated_at}} ->
          {:ok, count_remaining}

        _ ->
          {:ok, limit}
      end
    else
      {:ok, :infinity}
    end
  end

  @doc """
  Resets rate limit for a given key.

  Useful for testing or administrative purposes.

  ## Examples

      iex> TinkEx.RateLimiter.reset("user_123")
      :ok
  """
  @spec reset(String.t()) :: :ok
  def reset(key) do
    if Config.rate_limiting_enabled?() do
      bucket_key = build_bucket_key(key)

      case Hammer.delete_buckets(bucket_key) do
        {:ok, _count} -> :ok
        _ -> :ok
      end
    else
      :ok
    end
  end

  @doc """
  Gets information about rate limit for a key.

  Returns current count, limit, and time until reset.

  ## Examples

      iex> TinkEx.RateLimiter.info("user_123")
      {:ok, %{
        count: 5,
        limit: 100,
        remaining: 95,
        resets_in_ms: 3540000
      }}
  """
  @spec info(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def info(key, opts \\ []) do
    if Config.rate_limiting_enabled?() do
      limit = Keyword.get(opts, :limit, @default_requests_per_hour)
      period_ms = Keyword.get(opts, :period, @default_period)

      bucket_key = build_bucket_key(key)

      case Hammer.inspect_bucket(bucket_key, period_ms, limit) do
        {:ok, {count, count_remaining, ms_to_next_bucket, _created_at, _updated_at}} ->
          {:ok,
           %{
             count: count,
             limit: limit,
             remaining: count_remaining,
             resets_in_ms: ms_to_next_bucket
           }}

        error ->
          {:error, error}
      end
    else
      {:ok, %{count: 0, limit: :infinity, remaining: :infinity, resets_in_ms: 0}}
    end
  end

  # Private Functions

  defp do_check(key, opts) do
    limit = Keyword.get(opts, :limit, @default_requests_per_hour)
    period_ms = Keyword.get(opts, :period, @default_period)

    bucket_key = build_bucket_key(key)

    emit_check_telemetry(key, limit, period_ms)

    case Hammer.check_rate(bucket_key, period_ms, limit) do
      {:allow, _count} ->
        :ok

      {:deny, _limit} ->
        emit_exceeded_telemetry(key, limit, period_ms)
        log_rate_limit_exceeded(key)
        {:error, :rate_limited}

      {:error, reason} ->
        Logger.error("[TinkEx.RateLimiter] Rate limit check failed: #{inspect(reason)}")
        # Fail open - allow the request
        :ok
    end
  end

  defp build_bucket_key(key) do
    "tink_ex:rate_limit:#{key}"
  end

  defp emit_check_telemetry(key, limit, period_ms) do
    :telemetry.execute(
      [:tink_ex, :rate_limit, :checked],
      %{},
      %{key: key, limit: limit, period_ms: period_ms}
    )
  end

  defp emit_exceeded_telemetry(key, limit, period_ms) do
    :telemetry.execute(
      [:tink_ex, :rate_limit, :exceeded],
      %{},
      %{key: key, limit: limit, period_ms: period_ms}
    )
  end

  defp log_rate_limit_exceeded(key) do
    Logger.warning("""
    [TinkEx.RateLimiter] Rate limit exceeded
    Key: #{key}
    """)
  end
end
