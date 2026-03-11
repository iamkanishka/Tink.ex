defmodule Tink.Client do
  @moduledoc """
  HTTP client for making requests to the Tink API with built-in caching.

  This module handles authentication, request building, and response parsing
  for all Tink API endpoints. It automatically caches GET requests for
  improved performance.

  ## Cache Key Design

  Cache keys are built from the full URL including query parameters, so different
  paginated or filtered requests produce independent cache entries:

      "user_abc:data:v2:accounts?pageSize=10&pageToken=ABC" → own entry
      "user_abc:data:v2:accounts?pageSize=10&pageToken=XYZ" → own entry
  """

  alias Tink.{Cache, Error}

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

  # ---------------------------------------------------------------------------
  # HTTP Methods with Caching Support
  # ---------------------------------------------------------------------------

  @doc """
  Performs a GET request with automatic caching.

  GET requests are cached based on the resource type with appropriate TTLs.
  Cache can be disabled per-request via `opts: [cache: false]`.
  """
  @spec get(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(%__MODULE__{cache: cache_enabled} = client, url, opts \\ []) do
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
  Performs a POST request and invalidates user cache on success.
  """
  @spec post(t(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(%__MODULE__{user_id: user_id} = client, url, body, opts \\ []) do
    result = do_post(client, url, body, opts)

    if user_id && match?({:ok, _}, result) do
      Cache.invalidate_user(user_id)
    end

    result
  end

  @doc """
  Performs a PUT request and invalidates user cache on success.
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
  Performs a PATCH request and invalidates user cache on success.
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
  Performs a DELETE request and invalidates user cache on success.
  """
  @spec delete(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(%__MODULE__{user_id: user_id} = client, url, opts \\ []) do
    result = do_delete(client, url, opts)

    if user_id && match?({:ok, _}, result) do
      Cache.invalidate_user(user_id)
    end

    result
  end

  # ---------------------------------------------------------------------------
  # Private Implementation Functions
  # ---------------------------------------------------------------------------

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

  # Unified: always returns {:ok, body} on success (body may be %{} for empty 204 responses)
  defp do_delete(client, url, _opts) do
    full_url = build_url(client.base_url, url)
    headers = build_headers(client)

    case client.adapter.delete(full_url, headers, timeout: client.timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, %{}}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, error} ->
        {:error, Error.from_http_error(error)}
    end
  end

  # ---------------------------------------------------------------------------
  # Cache Helper Functions
  # ---------------------------------------------------------------------------

  # Build a cache key that includes the full URL path AND query string so that
  # different paginated/filtered requests produce independent cache entries.
  # e.g.  user_abc:data:v2:accounts?pageSize=10&pageToken=ABC  →  own entry
  defp build_cache_key(%__MODULE__{user_id: nil}, url) do
    Cache.build_key(["public", encode_url(url)])
  end

  defp build_cache_key(%__MODULE__{user_id: user_id}, url) do
    Cache.build_key([user_id, encode_url(url)])
  end

  # Convert a URL path (with optional query string) into a compact cache key
  # component.  Query parameters are sorted for canonical ordering.
  defp encode_url(url) do
    case String.split(url, "?", parts: 2) do
      [path] ->
        path
        |> String.replace_leading("/", "")
        |> String.replace("/", ":")

      [path, query] ->
        normalized_path =
          path
          |> String.replace_leading("/", "")
          |> String.replace("/", ":")

        # Sort query params so order doesn't affect cache identity
        sorted_query =
          query
          |> URI.decode_query()
          |> Enum.sort_by(&elem(&1, 0))
          |> URI.encode_query()

        "#{normalized_path}?#{sorted_query}"
    end
  end

  # URL patterns whose GET responses may be cached, checked in order.
  @cacheable_patterns [
    "/api/v1/providers",
    "/api/v1/categories",
    "/api/v1/statistics",
    "/api/v1/credentials",
    "/data/v2/accounts",
    "/data/v2/investment-accounts",
    "/data/v2/loan-accounts",
    "/data/v2/transactions",
    "/data/v2/identities",
    "/finance-management/v1/business-budgets",
    "/finance-management/v1/cash-flow-summaries",
    "/finance-management/v1/financial-calendar"
  ]

  # Endpoints that must NEVER be cached even if they match a cacheable pattern.
  @non_cacheable_patterns [
    "/oauth",
    "/user/create",
    "/user/delete",
    "/authorization-grant",
    "/link/v1/session",
    "/risk/",
    "/connector/",
    "/reconciliations",
    "/attachments"
  ]

  defp cacheable?(url) do
    Enum.any?(@cacheable_patterns, &String.contains?(url, &1)) &&
      not Enum.any?(@non_cacheable_patterns, &String.contains?(url, &1))
  end

  defp detect_resource_type(url) do
    cond do
      String.contains?(url, "/providers") -> :providers
      String.contains?(url, "/categories") -> :categories
      String.contains?(url, "investment-accounts") -> :accounts
      String.contains?(url, "loan-accounts") -> :accounts
      String.contains?(url, "/balances") -> :balances
      String.contains?(url, "/accounts") -> :accounts
      String.contains?(url, "/transactions") -> :transactions
      String.contains?(url, "/statistics") -> :statistics
      String.contains?(url, "/credentials") -> :credentials
      String.contains?(url, "/identities") -> :users
      String.contains?(url, "/cash-flow") -> :statistics
      String.contains?(url, "/business-budgets") -> :default
      String.contains?(url, "/financial-calendar") -> :default
      true -> :default
    end
  end

  # ---------------------------------------------------------------------------
  # URL / Header Helpers
  # ---------------------------------------------------------------------------

  defp build_url(base_url, path), do: base_url <> path

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
