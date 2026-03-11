defmodule Tink.HTTPBehaviour do
  @moduledoc """
  Behaviour specification for HTTP client adapters.

  This module defines the contract that HTTP adapters must implement to work
  with Tink. By using a behaviour, we allow for easy swapping of HTTP
  clients and simplified testing with mocks.

  ## Implementing a Custom Adapter

  To create a custom HTTP adapter:

      defmodule MyApp.CustomHTTPAdapter do
        @behaviour Tink.HTTPBehaviour

        @impl true
        def request(method, url, body, headers, opts) do
          # Your implementation
        end

        @impl true
        def get(url, headers, opts), do: request(:get, url, nil, headers, opts)

        @impl true
        def post(url, body, headers, opts), do: request(:post, url, body, headers, opts)

        @impl true
        def put(url, body, headers, opts), do: request(:put, url, body, headers, opts)

        @impl true
        def patch(url, body, headers, opts), do: request(:patch, url, body, headers, opts)

        @impl true
        def delete(url, headers, opts), do: request(:delete, url, nil, headers, opts)
      end

  Then configure Tink to use it:

      config :tink,
        http_adapter: MyApp.CustomHTTPAdapter

  ## Testing

  For testing, you can use a mock adapter:

      defmodule MyApp.MockHTTPAdapter do
        @behaviour Tink.HTTPBehaviour

        @impl true
        def request(_method, _url, _body, _headers, _opts) do
          {:ok, %{status: 200, headers: [], body: %{"data" => "test"}}}
        end

        # Implement other callbacks...
      end
  """

  @type method :: :get | :post | :put | :patch | :delete | :head | :options
  @type url :: String.t()
  @type body :: map() | String.t() | nil
  @type headers :: [{String.t(), String.t()}]
  @type opts :: keyword()

  @type response :: %{
          status: non_neg_integer(),
          headers: headers(),
          body: term()
        }

  @type error :: %{
          type: atom(),
          reason: term()
        }

  @doc """
  Performs an HTTP request with the specified method.

  ## Parameters

    * `method` - HTTP method (:get, :post, :put, :patch, :delete)
    * `url` - Full URL to request
    * `body` - Request body (map, string, or nil)
    * `headers` - List of header tuples
    * `opts` - Options including timeout, retries, etc.

  ## Returns

    * `{:ok, response}` - Successful response with status, headers, and body
    * `{:error, error}` - Request failed with error details

  ## Examples

      {:ok, response} = adapter.request(
        :get,
        "https://api.tink.com/api/v1/providers",
        nil,
        [{"authorization", "Bearer token"}],
        timeout: 5000
      )
  """
  @callback request(method(), url(), body(), headers(), opts()) ::
              {:ok, response()} | {:error, error()}

  @doc """
  Performs an HTTP GET request.

  ## Parameters

    * `url` - Full URL to request
    * `headers` - List of header tuples
    * `opts` - Options including timeout, retries, etc.

  ## Returns

    * `{:ok, response}` - Successful response
    * `{:error, error}` - Request failed

  ## Examples

      {:ok, response} = adapter.get(
        "https://api.tink.com/api/v1/providers",
        [{"authorization", "Bearer token"}],
        timeout: 5000
      )
  """
  @callback get(url(), headers(), opts()) :: {:ok, response()} | {:error, error()}

  @doc """
  Performs an HTTP POST request.

  ## Parameters

    * `url` - Full URL to request
    * `body` - Request body (map or string)
    * `headers` - List of header tuples
    * `opts` - Options including timeout, retries, etc.

  ## Returns

    * `{:ok, response}` - Successful response
    * `{:error, error}` - Request failed

  ## Examples

      {:ok, response} = adapter.post(
        "https://api.tink.com/api/v1/user/create",
        %{external_user_id: "user123"},
        [{"content-type", "application/json"}],
        timeout: 5000
      )
  """
  @callback post(url(), body(), headers(), opts()) :: {:ok, response()} | {:error, error()}

  @doc """
  Performs an HTTP PUT request.

  ## Parameters

    * `url` - Full URL to request
    * `body` - Request body (map or string)
    * `headers` - List of header tuples
    * `opts` - Options including timeout, retries, etc.

  ## Returns

    * `{:ok, response}` - Successful response
    * `{:error, error}` - Request failed
  """
  @callback put(url(), body(), headers(), opts()) :: {:ok, response()} | {:error, error()}

  @doc """
  Performs an HTTP PATCH request.

  ## Parameters

    * `url` - Full URL to request
    * `body` - Request body (map or string)
    * `headers` - List of header tuples
    * `opts` - Options including timeout, retries, etc.

  ## Returns

    * `{:ok, response}` - Successful response
    * `{:error, error}` - Request failed
  """
  @callback patch(url(), body(), headers(), opts()) :: {:ok, response()} | {:error, error()}

  @doc """
  Performs an HTTP DELETE request.

  ## Parameters

    * `url` - Full URL to request
    * `headers` - List of header tuples
    * `opts` - Options including timeout, retries, etc.

  ## Returns

    * `{:ok, response}` - Successful response
    * `{:error, error}` - Request failed

  ## Examples

      {:ok, response} = adapter.delete(
        "https://api.tink.com/api/v1/credentials/cred123",
        [{"authorization", "Bearer token"}],
        timeout: 5000
      )
  """
  @callback delete(url(), headers(), opts()) :: {:ok, response()} | {:error, error()}
end
