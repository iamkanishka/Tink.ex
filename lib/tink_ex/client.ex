defmodule TinkEx.Client do
  @moduledoc """
  HTTP client for making requests to the Tink API with built-in caching.

  This module handles authentication, request building, and response parsing
  for all Tink API endpoints. It automatically caches GET requests for
  improved performance.
  """

  alias TinkEx.{Config, Error, HTTPAdapter, Cache}

  @type t :: %__MODULE__{
          base_url: String.t(),
          client_id: String.t(),
          client_secret: String.t(),
          access_token: String.t() | nil,
          user_id: String.t() | nil,
          timeout: integer(),
          adapter: module(),
          cache: boolean()
        }

  defstruct [
    :base_url,
    :client_id,
    :client_secret,
    :access_token,
    :user_id,
    :timeout,
    :adapter,
    cache: true
  ]

  # HTTP Methods with Caching Support

  @doc """
  Performs a GET request with automatic caching.

  GET requests are cached based on the resource type with appropriate TTLs.
  Cache can be disabled per-request or globally.
  """
  @spec get(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(%__MODULE__{cache: cache_enabled} = client, url, opts \\ []) do
    # Allow per-request cache override
    use_cache = Keyword.get(opts, :cache, cache_enabled)

    if use_cache && cacheable?(url) do
      cache_key = build_cache_key(client, url)
      resource_type = detect_resource_type(url)

      Cache.fetch(
        cache_key,
        fn -> do_get(client, url) end,
        resource_type: resource_type
      )
    else
      do_get(client, url)
    end
  end

  @doc """
  Performs a POST request and invalidates cache.

  POST requests modify data, so they invalidate the user's cache.
  """
  @spec post(t(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(%__MODULE__{user_id: user_id} = client, url, body, opts \\ []) do
    result = do_post(client, url, body, opts)

    # Invalidate user cache after mutations
    if user_id && match?({:ok, _}, result) do
      Cache.invalidate_user(user_id)
    end

    result
  end

  @doc """
  Performs a PUT request and invalidates cache.
  """
  @spec put(t(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def put(%__MODULE__{user_id: user_id} = client, url, body, opts \\ []) do
    result = do_put(client, url, body, opts)

    if user_id && match?({:ok, _}, result) do
      Cache.invalidate_user(user_id)
    end

    result
  end

  @doc """
  Performs a PATCH request and invalidates cache.
  """
  @spec patch(t(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def patch(%__MODULE__{user_id: user_id} = client, url, body, opts \\ []) do
    result = do_patch(client, url, body, opts)

    if user_id && match?({:ok, _}, result) do
      Cache.invalidate_user(user_id)
    end

    result
  end

  @doc """
  Performs a DELETE request and invalidates cache.
  """
  @spec delete(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(%__MODULE__{user_id: user_id} = client, url, opts \\ []) do
    result = do_delete(client, url, opts)

    if user_id && match?({:ok, _}, result) do
      Cache.invalidate_user(user_id)
    end

    result
  end

  # Private Implementation Functions

  defp do_get(client, url) do
    full_url = build_url(client.base_url, url)
    headers = build_headers(client)

    case client.adapter.get(full_url, headers, timeout: client.timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, error} ->
        {:error, Error.from_http_error(error)}
    end
  end

  defp do_post(client, url, body, opts) do
    full_url = build_url(client.base_url, url)
    headers = build_headers(client, opts)

    case client.adapter.post(full_url, body, headers, timeout: client.timeout) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, Error.from_response(status, response_body)}

      {:error, error} ->
        {:error, Error.from_http_error(error)}
    end
  end

  defp do_put(client, url, body, opts) do
    full_url = build_url(client.base_url, url)
    headers = build_headers(client, opts)

    case client.adapter.put(full_url, body, headers, timeout: client.timeout) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, Error.from_response(status, response_body)}

      {:error, error} ->
        {:error, Error.from_http_error(error)}
    end
  end

  defp do_patch(client, url, body, opts) do
    full_url = build_url(client.base_url, url)
    headers = build_headers(client, opts)

    case client.adapter.patch(full_url, body, headers, timeout: client.timeout) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, Error.from_response(status, response_body)}

      {:error, error} ->
        {:error, Error.from_http_error(error)}
    end
  end

  defp do_delete(client, url, _opts) do
    full_url = build_url(client.base_url, url)
    headers = build_headers(client)

    case client.adapter.delete(full_url, headers, timeout: client.timeout) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, error} ->
        {:error, Error.from_http_error(error)}
    end
  end

  # Cache Helper Functions

  defp build_cache_key(%__MODULE__{user_id: nil}, url) do
    # Public/unauthenticated endpoints
    Cache.build_key(["public", normalize_url(url)])
  end

  defp build_cache_key(%__MODULE__{user_id: user_id}, url) do
    # User-specific endpoints
    Cache.build_key([user_id, normalize_url(url)])
  end

  defp normalize_url(url) do
    # Remove query params and normalize for caching
    url
    |> String.split("?")
    |> List.first()
    |> String.replace(~r/^\//, "")
    |> String.replace("/", ":")
  end

  defp cacheable?(url) do
    # Only cache GET requests for certain endpoints
    cacheable_patterns = [
      "/providers",
      "/categories",
      "/accounts",
      "/transactions",
      "/statistics",
      "/investment-accounts",
      "/loan-accounts"
    ]

    # Don't cache sensitive or verification endpoints
    non_cacheable_patterns = [
      "/oauth",
      "/user/create",
      "/authorization-grant",
      "/account-check",
      "/income-check",
      "/expense-check",
      "/risk",
      "/payment"
    ]

    Enum.any?(cacheable_patterns, &String.contains?(url, &1)) &&
      not Enum.any?(non_cacheable_patterns, &String.contains?(url, &1))
  end

  defp detect_resource_type(url) do
    cond do
      String.contains?(url, "/providers") -> :providers
      String.contains?(url, "/categories") -> :categories
      String.contains?(url, "/accounts") && String.contains?(url, "/investment") -> :accounts
      String.contains?(url, "/accounts") && String.contains?(url, "/loan") -> :accounts
      String.contains?(url, "/accounts") -> :accounts
      String.contains?(url, "/transactions") -> :transactions
      String.contains?(url, "/statistics") -> :statistics
      String.contains?(url, "/credentials") -> :credentials
      String.contains?(url, "/balances") -> :balances
      true -> :default
    end
  end

  # Existing helper functions (unchanged)

  defp build_url(base_url, path) do
    base_url <> path
  end

  defp build_headers(%__MODULE__{access_token: token}, opts \\ []) do
    base_headers = [
      {"accept", "application/json"},
      {"content-type", Keyword.get(opts, :content_type, "application/json")}
    ]

    if token do
      [{"authorization", "Bearer #{token}"} | base_headers]
    else
      base_headers
    end
  end
end
