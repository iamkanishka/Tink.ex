defmodule Tink.HTTPAdapter do
  @moduledoc """
  Production HTTP client implementation using Finch.

  This module implements the `Tink.HTTPBehaviour` interface and provides
  a high-performance HTTP client built on top of Finch and Mint.

  ## Features

  - ⚡ Connection pooling via Finch
  - 🔄 Automatic retries with exponential backoff
  - ⏱️ Configurable timeouts
  - 📊 Telemetry integration
  - 🔍 Request/response logging
  - 🌐 HTTP/1.1 and HTTP/2 support

  ## Configuration

  The adapter respects Tink configuration:

      config :tink,
        timeout: 30_000,
        max_retries: 3,
        pool_size: 32

  ## Telemetry

  Emits the following telemetry events:

  - `[:tink, :request, :start]` - Request initiated
  - `[:tink, :request, :stop]` - Request completed
  - `[:tink, :request, :exception]` - Request failed

  ## Examples

      # Direct usage
      {:ok, response} = Tink.HTTPAdapter.request(
        :get,
        "https://api.tink.com/api/v1/providers",
        nil,
        [{"authorization", "Bearer token"}],
        timeout: 5_000
      )

      # Used automatically by Tink.Client
      client = Tink.client()
      {:ok, accounts} = Tink.Accounts.list(client)
  """

  @behaviour Tink.HTTPBehaviour

  require Logger

  alias Tink.{Config, Retry}

  @default_timeout 30_000
  @default_receive_timeout 30_000

  @spec request(atom(), String.t(), term(), list(), keyword()) :: {:ok, map()} | {:error, map()}
  @impl true
  def request(method, url, body, headers, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    receive_timeout = Keyword.get(opts, :receive_timeout, @default_receive_timeout)
    retry_opts = Keyword.get(opts, :retry, true)

    metadata = %{
      method: method,
      url: url,
      headers: headers,
      opts: opts
    }

    :telemetry.execute(
      [:tink, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    start_time = System.monotonic_time()

    result =
      if retry_opts do
        Retry.with_retry(fn -> do_request(method, url, body, headers, timeout, receive_timeout) end)
      else
        do_request(method, url, body, headers, timeout, receive_timeout)
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, response} = success ->
        :telemetry.execute(
          [:tink, :request, :stop],
          %{duration: duration},
          Map.merge(metadata, %{status: response.status, response: response})
        )

        log_request(method, url, response.status, duration)
        success

      {:error, error} = failure ->
        :telemetry.execute(
          [:tink, :request, :exception],
          %{duration: duration},
          Map.merge(metadata, %{error: error})
        )

        log_error(method, url, error)
        failure
    end
  end

  @spec get(String.t(), list(), keyword()) :: {:ok, map()} | {:error, map()}
  @impl true
  def get(url, headers, opts \\ []) do
    request(:get, url, nil, headers, opts)
  end

  @spec post(String.t(), term(), list(), keyword()) :: {:ok, map()} | {:error, map()}
  @impl true
  def post(url, body, headers, opts \\ []) do
    request(:post, url, body, headers, opts)
  end

  @spec put(String.t(), term(), list(), keyword()) :: {:ok, map()} | {:error, map()}
  @impl true
  def put(url, body, headers, opts \\ []) do
    request(:put, url, body, headers, opts)
  end

  @spec patch(String.t(), term(), list(), keyword()) :: {:ok, map()} | {:error, map()}
  @impl true
  def patch(url, body, headers, opts \\ []) do
    request(:patch, url, body, headers, opts)
  end

  @spec delete(String.t(), list(), keyword()) :: {:ok, map()} | {:error, map()}
  @impl true
  def delete(url, headers, opts \\ []) do
    request(:delete, url, nil, headers, opts)
  end

  # Private Functions

  defp do_request(method, url, body, headers, timeout, receive_timeout) do
    with {:ok, encoded_body} <- encode_body(body, headers),
         {:ok, request} <- build_request(method, url, encoded_body, headers),
         {:ok, response} <-
           execute_request(request, timeout, receive_timeout),
         {:ok, decoded_response} <- decode_response(response) do
      {:ok, decoded_response}
    else
      {:error, _} = error -> error
    end
  end

  defp encode_body(nil, _headers), do: {:ok, nil}
  defp encode_body(body, _headers) when is_binary(body), do: {:ok, body}

  defp encode_body(body, headers) when is_map(body) or is_list(body) do
    # Check if content-type is form-urlencoded
    content_type =
      Enum.find_value(headers, fn
        {key, value} when key in ["content-type", "Content-Type"] -> value
        _ -> nil
      end)

    if content_type =~ "application/x-www-form-urlencoded" do
      {:ok, URI.encode_query(body)}
    else
      case Jason.encode(body) do
        {:ok, encoded} -> {:ok, encoded}
        {:error, reason} -> {:error, %{type: :encode_error, reason: reason}}
      end
    end
  end

  def build_request(method, url, headers, body) do
    request = Finch.build(method, url, headers, body)
    {:ok, request}
  rescue
    error ->
      {:error, %{type: :build_error, reason: error}}
  end

  defp execute_request(request, timeout, receive_timeout) do
    case Finch.request(request, Tink.Finch,
           pool_timeout: timeout,
           receive_timeout: receive_timeout
         ) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok,
         %{
           status: status,
           headers: headers,
           body: body
         }}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, %{type: :timeout, reason: "Request timed out"}}

      {:error, %Mint.TransportError{reason: :closed}} ->
        {:error, %{type: :network_error, reason: "Connection closed"}}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, %{type: :network_error, reason: reason}}

      {:error, reason} ->
        {:error, %{type: :unknown, reason: reason}}
    end
  end

  # Finch always returns binary bodies, so this clause is the only reachable path.
  # Non-JSON bodies (e.g. PDFs, binary downloads) are returned as-is.
  defp decode_response(%{body: body} = response) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        {:ok, %{response | body: decoded}}

      {:error, %Jason.DecodeError{}} ->
        # Body is not JSON (e.g. PDF, binary download) — return raw response as-is.
        {:ok, response}
    end
  end

  defp log_request(method, url, status, duration) do
    if Config.get(:debug_mode, false) do
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      Logger.debug("""
      [Tink.HTTPAdapter]
      Request: #{method} #{url}
      Status: #{status}
      Duration: #{duration_ms}ms
      """)
    end
  end

  defp log_error(method, url, error) do
    Logger.error("""
    [Tink.HTTPAdapter]
    Request failed: #{method} #{url}
    Error: #{inspect(error)}
    """)
  end
end
