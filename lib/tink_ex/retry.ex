defmodule TinkEx.Retry do
  @moduledoc """
  Retry logic with exponential backoff for TinkEx.

  Automatically retries failed requests with configurable retry strategies.

  ## Features

  - Exponential backoff with jitter
  - Configurable max retries
  - Only retries transient errors
  - Telemetry events

  ## Configuration

      config :tink_ex,
        max_retries: 3,
        retry_base_delay: 1000,
        retry_max_delay: 30000

  ## Examples

      # Retry a function
      result = TinkEx.Retry.with_retry(fn ->
        make_api_call()
      end)

      # Custom retry options
      result = TinkEx.Retry.with_retry(
        fn -> make_api_call() end,
        max_attempts: 5,
        base_delay: 500
      )
  """

  require Logger

  alias TinkEx.{Error, Config}

  @default_max_attempts 3
  @default_base_delay 1000  # 1 second
  @default_max_delay 30_000  # 30 seconds
  @default_jitter_factor 0.1

  @type retry_option ::
          {:max_attempts, pos_integer()}
          | {:base_delay, pos_integer()}
          | {:max_delay, pos_integer()}
          | {:jitter_factor, float()}
          | {:retry_fn, (Error.t() -> boolean())}

  @type retry_options :: [retry_option()]

  @doc """
  Executes a function with retry logic.

  ## Options

    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:base_delay` - Base delay between retries in ms (default: 1000)
    * `:max_delay` - Maximum delay between retries in ms (default: 30000)
    * `:jitter_factor` - Jitter factor for randomization (default: 0.1)
    * `:retry_fn` - Custom function to determine if error is retryable

  ## Examples

      # Simple retry
      {:ok, result} = TinkEx.Retry.with_retry(fn ->
        TinkEx.Accounts.list(client)
      end)

      # Custom retry logic
      {:ok, result} = TinkEx.Retry.with_retry(
        fn -> make_request() end,
        max_attempts: 5,
        base_delay: 2000,
        retry_fn: &custom_retry?/1
      )
  """
  @spec with_retry((() -> term()), retry_options()) :: term()
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, get_max_attempts())
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    jitter_factor = Keyword.get(opts, :jitter_factor, @default_jitter_factor)
    retry_fn = Keyword.get(opts, :retry_fn, &default_retry?/1)

    do_retry(fun, 1, max_attempts, base_delay, max_delay, jitter_factor, retry_fn)
  end

  @doc """
  Checks if an error should be retried using default logic.

  ## Examples

      iex> error = %TinkEx.Error{type: :network_error}
      iex> TinkEx.Retry.should_retry?(error)
      true

      iex> error = %TinkEx.Error{type: :validation_error}
      iex> TinkEx.Retry.should_retry?(error)
      false
  """
  @spec should_retry?(Error.t() | term()) :: boolean()
  def should_retry?(%Error{} = error) do
    Error.retryable?(error)
  end

  def should_retry?(_), do: false

  @doc """
  Calculates delay for a specific retry attempt with exponential backoff and jitter.

  ## Examples

      iex> TinkEx.Retry.calculate_delay(1, 1000, 30000, 0.1)
      # Returns value around 1000ms with ±10% jitter

      iex> TinkEx.Retry.calculate_delay(3, 1000, 30000, 0.1)
      # Returns value around 4000ms with ±10% jitter
  """
  @spec calculate_delay(pos_integer(), pos_integer(), pos_integer(), float()) :: pos_integer()
  def calculate_delay(attempt, base_delay, max_delay, jitter_factor) do
    # Exponential backoff: base_delay * 2^(attempt - 1)
    exponential_delay = base_delay * :math.pow(2, attempt - 1)

    # Cap at max_delay
    capped_delay = min(exponential_delay, max_delay)

    # Add jitter
    add_jitter(capped_delay, jitter_factor)
  end

  # Private Functions

  defp do_retry(fun, attempt, max_attempts, base_delay, max_delay, jitter_factor, retry_fn) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, error} = failure ->
        should_retry = retry_fn.(error)
        has_more_attempts = attempt < max_attempts

        if should_retry and has_more_attempts do
          delay = calculate_delay(attempt, base_delay, max_delay, jitter_factor)

          log_retry(error, attempt, max_attempts, delay)
          emit_retry_telemetry(error, attempt, delay)

          Process.sleep(delay)

          do_retry(
            fun,
            attempt + 1,
            max_attempts,
            base_delay,
            max_delay,
            jitter_factor,
            retry_fn
          )
        else
          if not should_retry do
            log_no_retry(error, "error not retryable")
          else
            log_no_retry(error, "max attempts reached")
          end

          failure
        end

      other ->
        # Non-error result, return as-is
        other
    end
  end

  defp default_retry?(%Error{} = error), do: Error.retryable?(error)
  defp default_retry?(_), do: false

  defp add_jitter(delay, jitter_factor) do
    jitter_range = delay * jitter_factor
    jitter = :rand.uniform() * jitter_range * 2 - jitter_range
    round(delay + jitter)
  end

  defp get_max_attempts do
    Config.get(:max_retries, @default_max_attempts)
  end

  defp log_retry(error, attempt, max_attempts, delay) do
    if Config.debug_mode?() do
      Logger.debug("""
      [TinkEx.Retry] Retrying request
      Attempt: #{attempt}/#{max_attempts}
      Error: #{Error.format(error)}
      Delay: #{delay}ms
      """)
    end
  end

  defp log_no_retry(error, reason) do
    Logger.debug("""
    [TinkEx.Retry] Not retrying request
    Reason: #{reason}
    Error: #{Error.format(error)}
    """)
  end

  defp emit_retry_telemetry(error, attempt, delay) do
    :telemetry.execute(
      [:tink_ex, :retry, :attempt],
      %{attempt: attempt, delay: delay},
      %{error: error}
    )
  end
end
