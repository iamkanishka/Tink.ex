defmodule Tink.RateLimiter do
  @moduledoc """
  Rate limiting for Tink API requests using Hammer 7.2.

  Uses a private `Tink.RateLimiter.Backend` module backed by Hammer's
  fixed-window ETS algorithm. The backend process is supervised by
  `Tink.Application` and must be running before any rate-limit functions
  are called.

  ## Algorithm

  Fixed window (`Hammer.ETS.FixWindow`) is used because Tink's rate limits
  are expressed as "N requests per hour" — exactly what a fixed window
  enforces with minimal overhead.

  ## Configuration

      config :tink,
        enable_rate_limiting: true

  Optionally tune the cleanup interval (default: every 5 minutes):

      config :tink, Tink.RateLimiter.Backend,
        clean_period: :timer.minutes(5)

  ## Hammer 7.2 API used

  `Backend.hit(key, scale_ms, limit)` — increments the counter and checks
  the limit atomically. Returns `{:allow, count}` or `{:deny, ms_to_reset}`.

  `Backend.get(key, scale_ms)` — returns the current count without incrementing.

  ## Telemetry

  Emits:
  - `[:tink, :rate_limit, :checked]` — check performed
  - `[:tink, :rate_limit, :exceeded]` — limit exceeded
  """

  require Logger

  alias Tink.Config

  @default_limit 100
  @default_period :timer.hours(1)

  # ---------------------------------------------------------------------------
  # Hammer 7.2 backend module
  #
  # `use Hammer, backend: :ets, algorithm: :fix_window` injects:
  #   - start_link/1   — starts the ETS table owner / cleanup GenServer
  #   - hit/3          — hit(key, scale_ms, limit) :: {:allow, count} | {:deny, ms_to_reset}
  #   - hit/4          — hit(key, scale_ms, limit, increment)
  #   - get/2          — get(key, scale_ms) :: non_neg_integer()
  #   - inc/3          — inc(key, scale_ms, increment) :: non_neg_integer()
  #
  # Must be added to the supervision tree via Tink.Application.
  # ---------------------------------------------------------------------------

  defmodule Backend do
    @moduledoc false
    use Hammer, backend: :ets, algorithm: :fix_window
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Checks whether a request is within the configured rate limit.

  Increments the counter for `key` in the current window. Returns `:ok` if
  the request is allowed, or `{:error, :rate_limited}` if the limit is exceeded.

  ## Parameters

    * `key` - Bucket identifier, e.g. a user ID or operation name
    * `opts` - Options:
      * `:limit` - Maximum requests per window (default: 100)
      * `:period` - Window duration in milliseconds (default: 1 hour)

  ## Examples

      iex> Tink.RateLimiter.check("user_123")
      :ok

      iex> Tink.RateLimiter.check("user_123", limit: 50, period: :timer.minutes(30))
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
  Returns the number of requests remaining in the current window for `key`.

  Does **not** increment the counter. Returns `{:ok, :infinity}` when rate
  limiting is disabled.

  ## Examples

      iex> Tink.RateLimiter.remaining("user_123")
      {:ok, 95}

      iex> Tink.RateLimiter.remaining("unknown_key")
      {:ok, 100}
  """
  @spec remaining(String.t(), keyword()) :: {:ok, non_neg_integer() | :infinity}
  def remaining(key, opts \\ []) do
    if Config.rate_limiting_enabled?() do
      limit = Keyword.get(opts, :limit, @default_limit)
      period_ms = Keyword.get(opts, :period, @default_period)
      bucket_key = build_bucket_key(key)

      count = Backend.get(bucket_key, period_ms)
      {:ok, max(0, limit - count)}
    else
      {:ok, :infinity}
    end
  end

  @doc """
  Returns detailed rate limit information for `key`.

  ## Returns

    * `{:ok, map}` — Map with `:count`, `:limit`, `:remaining`
    * `{:ok, map}` — With `:resets_in_ms` set to `0` when rate limiting is off

  ## Examples

      iex> Tink.RateLimiter.info("user_123")
      {:ok, %{count: 5, limit: 100, remaining: 95}}
  """
  @spec info(String.t(), keyword()) :: {:ok, map()}
  def info(key, opts \\ []) do
    if Config.rate_limiting_enabled?() do
      limit = Keyword.get(opts, :limit, @default_limit)
      period_ms = Keyword.get(opts, :period, @default_period)
      bucket_key = build_bucket_key(key)

      count = Backend.get(bucket_key, period_ms)

      {:ok,
       %{
         count: count,
         limit: limit,
         remaining: max(0, limit - count)
       }}
    else
      {:ok, %{count: 0, limit: :infinity, remaining: :infinity}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_check(key, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    period_ms = Keyword.get(opts, :period, @default_period)
    bucket_key = build_bucket_key(key)

    emit_check_telemetry(key, limit, period_ms)

    # Backend.hit/3 atomically increments the counter and checks the limit.
    # {:allow, count}        — request is within the limit
    # {:deny, ms_to_reset}   — limit exceeded; ms_to_reset is time until the window resets
    case Backend.hit(bucket_key, period_ms, limit) do
      {:allow, _count} ->
        :ok

      {:deny, _ms_to_reset} ->
        emit_exceeded_telemetry(key, limit, period_ms)
        log_rate_limit_exceeded(key)
        {:error, :rate_limited}
    end
  end

  defp build_bucket_key(key), do: "tink:rate_limit:#{key}"

  defp emit_check_telemetry(key, limit, period_ms) do
    :telemetry.execute(
      [:tink, :rate_limit, :checked],
      %{},
      %{key: key, limit: limit, period_ms: period_ms}
    )
  end

  defp emit_exceeded_telemetry(key, limit, period_ms) do
    :telemetry.execute(
      [:tink, :rate_limit, :exceeded],
      %{},
      %{key: key, limit: limit, period_ms: period_ms}
    )
  end

  defp log_rate_limit_exceeded(key) do
    Logger.warning("[Tink.RateLimiter] Rate limit exceeded for key: #{key}")
  end
end
