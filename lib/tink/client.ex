defmodule Tink.Client do
  @moduledoc """
  Represents an authenticated Tink API client.

  ## Fields

  - `:access_token` — Bearer token (required)
  - `:refresh_token` — refresh token for obtaining new access tokens (if provided)
  - `:token_type` — "bearer" (default)
  - `:expires_at` — `DateTime` expiry; nil means never checked
  - `:scope` — space-separated token scopes
  - `:id_hint` — user hint returned by Tink in token responses
  - `:auto_refresh` — re-fetch a client credentials token on 401
  - `:cache` — set `false` to bypass caching for all calls on this client
  - `:rate_limit_key` — Hammer bucket key; defaults to `Tink.Config.client_id()`
  - `:adapter` — HTTP adapter module (default: `Tink.Config.http_adapter()`)

  ## Creating clients

      {:ok, client} = Tink.Auth.client_credentials(scope: "authorization:grant user:create")
      {:ok, client} = Tink.Auth.user_client(auth_code)
      client        = Tink.Client.new(access_token: "bearer_abc123")

  ## Bypassing cache per-client

      no_cache_client = %{user_client | cache: false}
      {:ok, accounts} = Tink.Accounts.list(no_cache_client)

  ## Tracing requests

  Pass `:client_trace_id` to tag requests for tracing. Tink echoes it back
  in the `X-Client-Trace-ID` response header:

      Tink.Accounts.list(client, client_trace_id: "my-trace-abc-123")

  ## Idempotency

  For POST requests that must not be duplicated (e.g. payments), pass an
  `:idempotency_key`. Tink de-duplicates requests with the same key for 24h:

      Tink.Payments.create(client, params, idempotency_key: idempotency_uuid)

  ## Per-call retry override

      Tink.Transactions.list(client, max_retries: 0)   # disable retry
      Tink.Accounts.get(client, "id", max_retries: 5)  # increase retries

  """

  alias Tink.{Config, Error, RateLimiter, Telemetry}

  @type t :: %__MODULE__{
          access_token: String.t(),
          refresh_token: String.t() | nil,
          token_type: String.t(),
          expires_at: DateTime.t() | nil,
          scope: String.t() | nil,
          id_hint: String.t() | nil,
          auto_refresh: boolean(),
          cache: boolean(),
          rate_limit_key: String.t() | nil,
          adapter: module() | nil
        }

  defstruct [
    :access_token,
    :refresh_token,
    :expires_at,
    :scope,
    :id_hint,
    :rate_limit_key,
    token_type: "bearer",
    auto_refresh: false,
    cache: true,
    adapter: nil
  ]

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      access_token: Keyword.fetch!(opts, :access_token),
      refresh_token: Keyword.get(opts, :refresh_token),
      token_type: Keyword.get(opts, :token_type, "bearer"),
      expires_at: Keyword.get(opts, :expires_at),
      scope: Keyword.get(opts, :scope),
      id_hint: Keyword.get(opts, :id_hint),
      auto_refresh: Keyword.get(opts, :auto_refresh, false),
      cache: Keyword.get(opts, :cache, true),
      rate_limit_key: Keyword.get(opts, :rate_limit_key),
      adapter: Keyword.get(opts, :adapter)
    }
  end

  @doc "Returns true if the access token has passed its expiry time."
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: exp}) do
    DateTime.compare(DateTime.utc_now(), exp) != :lt
  end

  @doc "Whether caching is enabled for this client."
  @spec cache_enabled?(t()) :: boolean()
  def cache_enabled?(%__MODULE__{cache: false}), do: false
  def cache_enabled?(_client), do: Config.cache_enabled?()

  # ── Public request helpers ────────────────────────────────────────────────────

  @spec get(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, path, opts \\ []), do: request(client, :get, path, nil, opts)

  @spec post(t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(client, path, body \\ nil, opts \\ []), do: request(client, :post, path, body, opts)

  @spec put(t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
  def put(client, path, body \\ nil, opts \\ []), do: request(client, :put, path, body, opts)

  @spec patch(t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
  def patch(client, path, body \\ nil, opts \\ []), do: request(client, :patch, path, body, opts)

  @spec delete(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(client, path, opts \\ []), do: request(client, :delete, path, nil, opts)

  # ── Core request / retry / rate-limit pipeline ───────────────────────────────

  # Status codes that are NEVER retried — always return immediately
  @non_retryable [400, 401, 403, 404, 422]

  defp request(client, method, path, body, opts) do
    case check_rate_limit(client) do
      {:error, _} = rl_err ->
        rl_err

      :ok ->
        max_retries = Keyword.get(opts, :max_retries, Config.max_retries())
        do_request(client, method, path, body, opts, 0, max_retries)
    end
  end

  defp check_rate_limit(%__MODULE__{rate_limit_key: nil}), do: :ok

  defp check_rate_limit(%__MODULE__{rate_limit_key: key}) do
    case RateLimiter.check(key) do
      :ok ->
        :ok

      {:error, :rate_limited, _retry_after_ms} ->
        {:error,
         %Error{
           status: 429,
           code: "CLIENT_RATE_LIMITED",
           message: "Client-side rate limit exceeded. Retry later."
         }}
    end
  end

  defp do_request(client, method, path, body, opts, attempt, max) do
    start_time = System.monotonic_time()
    url = build_url(path)
    headers = build_headers(client, opts)
    enc_body = encode_body(body, headers)

    Telemetry.request_start(method, url)

    http_adapter = adapter(client)

    result =
      http_adapter.request(method, url, headers, enc_body, opts)
      |> parse_response()

    duration = System.monotonic_time() - start_time
    Telemetry.request_stop(method, url, result, duration)

    case result do
      # Never retry client errors
      {:error, %Error{status: s}} when s in @non_retryable ->
        result

      # Retry rate limit — respect Retry-After header if present
      {:error, %Error{status: 429, details: details}} when attempt < max ->
        delay = retry_after_delay(details) || jitter_backoff(attempt)
        Process.sleep(delay)
        do_request(client, method, path, body, opts, attempt + 1, max)

      # Retry server unavailability
      {:error, %Error{status: 503}} when attempt < max ->
        Process.sleep(jitter_backoff(attempt))
        do_request(client, method, path, body, opts, attempt + 1, max)

      # Retry network-level failures (no HTTP response)
      {:error, %Error{status: nil}} when attempt < max ->
        Process.sleep(jitter_backoff(attempt))
        do_request(client, method, path, body, opts, attempt + 1, max)

      other ->
        other
    end
  end

  # ── Internals ────────────────────────────────────────────────────────────────

  defp adapter(%__MODULE__{adapter: nil}), do: Config.http_adapter()
  defp adapter(%__MODULE__{adapter: a}), do: a

  defp build_url(path) when is_binary(path) do
    if String.starts_with?(path, "http"),
      do: path,
      else: Config.base_url() <> path
  end

  defp build_headers(client, opts) do
    content_type = Keyword.get(opts, :content_type, "application/json")
    extra = Keyword.get(opts, :headers, [])
    client_trace_id = Keyword.get(opts, :client_trace_id)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    base = [
      {"authorization", "Bearer #{client.access_token}"},
      {"content-type", content_type},
      {"accept", "application/json"},
      {"user-agent", "tink-elixir/#{tink_version()}"}
    ]

    # X-Client-Trace-ID — optional; Tink echoes it back for tracing/debugging
    base =
      if client_trace_id,
        do: [{"x-client-trace-id", client_trace_id} | base],
        else: base

    # Idempotency-Key — prevents duplicate POSTs; valid for 24h at Tink
    base =
      if idempotency_key,
        do: [{"idempotency-key", idempotency_key} | base],
        else: base

    base ++ extra
  end

  defp encode_body(nil, _headers), do: nil
  defp encode_body(body, _headers) when is_binary(body), do: body

  defp encode_body(body, headers) when is_map(body) do
    ct =
      Enum.find_value(headers, "application/json", fn
        {k, v} when is_binary(k) -> if String.downcase(k) == "content-type", do: v
        _ -> nil
      end)

    if String.contains?(ct, "application/x-www-form-urlencoded"),
      do: URI.encode_query(body),
      else: Jason.encode!(body)
  end

  # Reads the actual package version from the app spec rather than a
  # hardcoded literal, so the User-Agent header never goes stale on release.
  defp tink_version do
    case Application.spec(:tink, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "unknown"
    end
  end

  defp parse_response({:error, reason}) do
    {:error, Error.network(inspect(reason))}
  end

  defp parse_response({:ok, %{status: status, headers: headers, body: body}}) do
    request_id = get_header(headers, "x-tink-request-id")

    cond do
      status in 200..299 ->
        parse_ok_body(body)

      status == 204 ->
        {:ok, %{}}

      true ->
        {:error, Error.from_response(status, safe_decode(body), request_id)}
    end
  end

  defp parse_ok_body(b) when b in ["", nil], do: {:ok, %{}}

  defp parse_ok_body(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, Error.decode(inspect(reason))}
    end
  end

  defp safe_decode(body) do
    case Jason.decode(body) do
      {:ok, map} -> map
      _ -> %{"message" => body}
    end
  end

  defp get_header(headers, key) do
    Enum.find_value(headers, fn
      {k, v} when is_binary(k) -> if String.downcase(k) == key, do: v
      _ -> nil
    end)
  end

  # Parse Retry-After header value from the error response details
  # Tink may include retry_after_ms or we fall back to backoff
  defp retry_after_delay(%{"retryAfterMillis" => ms}) when is_integer(ms) and ms > 0, do: ms

  defp retry_after_delay(%{"retry_after" => secs}) when is_integer(secs) and secs > 0,
    do: secs * 1_000

  defp retry_after_delay(_), do: nil

  # Full-jitter exponential backoff: sleep between 0 and min(cap, base * 2^attempt)
  defp jitter_backoff(attempt) do
    base = Config.retry_delay()
    cap = 30_000
    ceiling = min(cap, round(base * :math.pow(2, attempt)))
    :rand.uniform(max(ceiling, 1))
  end

  # ── URL query param helper ────────────────────────────────────────────────────

  @doc """
  Append query params to a path, omitting nil values.

      Client.add_query("/data/v2/accounts", %{"pageSize" => 50, "pageToken" => nil})
      # => "/data/v2/accounts?pageSize=50"

  """
  @spec add_query(String.t(), keyword() | map()) :: String.t()
  def add_query(path, params) when params in [[], %{}], do: path

  def add_query(path, params) do
    query =
      params
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> URI.encode_query()

    if query == "", do: path, else: "#{path}?#{query}"
  end
end
