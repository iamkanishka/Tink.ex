defmodule Tink.RateLimiter do
  @moduledoc """
  Client-side rate limiting using Hammer (token bucket / ETS backend).

  Prevents your application from sending too many requests and hitting Tink's
  429 rate limit. Configured per `client_id` so multiple application clients
  share the same bucket.

  Per Tink's docs: rate limits are validated on a per-app-ID basis, and
  exceeding them returns an HTTP 429 Too Many Requests response. Tink does
  not publish an exact request-per-minute number — contact Tink support if
  you are consistently hitting 429s during expected use.

  ## Configuration

      config :tink,
        rate_limit: [
          enabled:          true,
          requests_per_min: 600,    # conservative client-side default — Tink
                                     # enforces its own per-app-ID server-side
                                     # limit but does not publish an exact
                                     # number; tune this to match your plan
          burst_size:       60      # max burst above the per-minute rate
        ]

  ## Disabling rate limiting

      config :tink, rate_limit: [enabled: false]

  ## Usage

  Rate limiting is applied automatically by `Tink.Client` before each request.
  You can also check or consume the bucket manually:

      case Tink.RateLimiter.check(client) do
        :ok                          -> # proceed
        {:error, :rate_limited, ms}  -> # wait ms milliseconds
      end

  ## Telemetry

  Emits `[:tink, :rate_limit, :check]` with metadata `%{key, allowed}`.
  """

  alias Tink.{Config, Telemetry}

  @default_rpm 600
  @default_burst 60
  @bucket_prefix "tink_rl:"

  @doc "Check and consume one token for the given client. Returns `:ok` or `{:error, :rate_limited, retry_after_ms}`."
  @spec check(String.t()) :: :ok | {:error, :rate_limited, non_neg_integer()}
  def check(client_key) do
    if enabled?() do
      do_check(client_key)
    else
      :ok
    end
  end

  @doc "Whether rate limiting is enabled per config."
  @spec enabled?() :: boolean()
  def enabled? do
    cfg = Config.rate_limit_cfg()
    Keyword.get(cfg, :enabled, true)
  end

  @doc "Return the configured requests-per-minute limit."
  @spec requests_per_minute() :: pos_integer()
  def requests_per_minute do
    cfg = Config.rate_limit_cfg()
    Keyword.get(cfg, :requests_per_min, @default_rpm)
  end

  @doc "Return the burst size."
  @spec burst_size() :: pos_integer()
  def burst_size do
    cfg = Config.rate_limit_cfg()
    Keyword.get(cfg, :burst_size, @default_burst)
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp do_check(client_key) do
    bucket = @bucket_prefix <> client_key
    scale_ms = 60_000
    limit = requests_per_minute()

    result = Hammer.check_rate(bucket, scale_ms, limit)
    Telemetry.rate_limit_check(client_key, match?({:allow, _}, result))

    case result do
      {:allow, _count} ->
        :ok

      {:deny, _limit} ->
        retry_after = compute_retry_after(scale_ms, limit)
        {:error, :rate_limited, retry_after}
    end
  end

  defp compute_retry_after(scale_ms, limit) do
    # How many ms until one token is available
    div(scale_ms, limit)
  end
end
