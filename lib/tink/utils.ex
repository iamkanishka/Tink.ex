defmodule Tink.Utils do
  @moduledoc """
  Internal utility helpers shared across all Tink API modules.

  Not part of the public API surface — subject to change without notice.
  """

  alias Tink.{Client, Error}

  # ── Map building helpers ──────────────────────────────────────────────────────

  @doc "Put `value` into `map` under `key` only when `value` is not nil."
  @spec put_if_present(map(), String.t(), any()) :: map()
  def put_if_present(map, _key, nil), do: map
  def put_if_present(map, key, value), do: Map.put(map, key, value)

  @doc "Put a list as a comma-joined string, only when list is not nil."
  @spec put_list_if_present(map(), String.t(), list() | nil) :: map()
  def put_list_if_present(map, _key, nil), do: map

  def put_list_if_present(map, key, list) when is_list(list) do
    Map.put(map, key, Enum.join(list, ","))
  end

  @doc "Build a params map from a keyword list, mapping atom keys to camelCase strings."
  @spec params_from_opts(keyword(), [{atom(), String.t()}]) :: map()
  def params_from_opts(opts, mappings) do
    Enum.reduce(mappings, %{}, fn {atom_key, string_key}, acc ->
      put_if_present(acc, string_key, Keyword.get(opts, atom_key))
    end)
  end

  # ── Pagination params ─────────────────────────────────────────────────────────

  @doc "Standard pagination params from opts."
  @spec pagination_params(keyword()) :: map()
  def pagination_params(opts) do
    %{}
    |> put_if_present("pageToken", Keyword.get(opts, :page_token))
    |> put_if_present("pageSize", Keyword.get(opts, :page_size))
  end

  # ── Cache key helpers ─────────────────────────────────────────────────────────

  @doc """
  A short prefix derived from a client token — used to scope cache keys per
  user session. Not a security boundary; purely for key namespacing.
  """
  @spec token_prefix(Client.t()) :: String.t()
  def token_prefix(%Client{access_token: token}) when is_binary(token) do
    String.slice(token, 0, 12)
  end

  def token_prefix(_), do: "unknown"

  @doc "Hash a params map to a stable string for use in cache keys."
  @spec params_hash(map()) :: String.t()
  def params_hash(params) do
    params |> :erlang.phash2() |> Integer.to_string()
  end

  # ── Polling helper ────────────────────────────────────────────────────────────

  @doc """
  Poll `fetch_fn` repeatedly until it returns a response matching `done_statuses`,
  or until the deadline is exceeded.

  Returns `{:ok, response}` on success, `{:error, :timeout}` on deadline, or
  `{:error, %Tink.Error{}}` if the fetch_fn returns an error status.

  ## Options
  - `:timeout_ms` — max wait time in ms (default: 30_000)
  - `:interval_ms` — sleep between polls in ms (default: 1_000)
  - `:failed_statuses` — list of statuses that mean terminal failure (default: `["FAILED", "ERROR"]`)
  """
  @spec poll_until(
          fetch_fn :: (-> {:ok, map()} | {:error, any()}),
          done_statuses :: [String.t()],
          opts :: keyword()
        ) :: {:ok, map()} | {:error, Error.t() | :timeout}
  def poll_until(fetch_fn, done_statuses, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    interval_ms = Keyword.get(opts, :interval_ms, 1_000)
    failed = Keyword.get(opts, :failed_statuses, ["FAILED", "ERROR", "CANCELLED"])
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_poll(fetch_fn, done_statuses, failed, interval_ms, deadline)
  end

  defp do_poll(fetch_fn, done_statuses, failed_statuses, interval_ms, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      handle_poll_result(
        fetch_fn.(),
        fetch_fn,
        done_statuses,
        failed_statuses,
        interval_ms,
        deadline
      )
    end
  end

  defp handle_poll_result(
         {:ok, %{"status" => status} = resp},
         fetch_fn,
         done_statuses,
         failed_statuses,
         interval_ms,
         deadline
       ) do
    cond do
      status in done_statuses -> {:ok, resp}
      status in failed_statuses -> {:error, Error.from_response(422, resp)}
      true -> wait_and_retry(fetch_fn, done_statuses, failed_statuses, interval_ms, deadline)
    end
  end

  defp handle_poll_result(
         {:ok, _in_progress},
         fetch_fn,
         done_statuses,
         failed_statuses,
         interval_ms,
         deadline
       ) do
    wait_and_retry(fetch_fn, done_statuses, failed_statuses, interval_ms, deadline)
  end

  defp handle_poll_result({:error, _} = err, _fetch_fn, _done, _failed, _interval, _deadline) do
    err
  end

  defp wait_and_retry(fetch_fn, done_statuses, failed_statuses, interval_ms, deadline) do
    Process.sleep(interval_ms)
    do_poll(fetch_fn, done_statuses, failed_statuses, interval_ms, deadline)
  end
end
