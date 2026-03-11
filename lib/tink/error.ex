defmodule Tink.Error do
  @moduledoc """
  Error struct and handling for Tink.

  All API errors are wrapped in this struct for consistent error handling.

  ## Error Types

  - `:api_error` - Tink API returned an error response
  - `:network_error` - Network/connection error
  - `:timeout` - Request timed out
  - `:authentication_error` - Auth failure
  - `:rate_limit_error` - Rate limit exceeded
  - `:validation_error` - Invalid parameters
  - `:decode_error` - Failed to decode response
  - `:market_mismatch` - Provider not available in requested market
  - `:unknown` - Unknown error

  ## Examples

      case Tink.Accounts.list(client) do
        {:ok, accounts} ->
          # Success

        {:error, %Tink.Error{type: :rate_limit_error}} ->
          # Handle rate limit

        {:error, %Tink.Error{status: 401}} ->
          # Handle unauthorized

        {:error, error} ->
          IO.inspect(error)
      end
  """

  @type error_type ::
          :api_error
          | :network_error
          | :timeout
          | :authentication_error
          | :rate_limit_error
          | :validation_error
          | :decode_error
          | :market_mismatch
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          status: integer() | nil,
          error_code: String.t() | nil,
          error_details: map() | nil,
          request_id: String.t() | nil,
          original_error: term() | nil
        }

  @enforce_keys [:type, :message]
  defstruct [
    :type,
    :message,
    :status,
    :error_code,
    :error_details,
    :request_id,
    :original_error
  ]

  @doc """
  Creates a new error struct.

  ## Examples

      iex> Tink.Error.new(type: :network_error, message: "Connection failed")
      %Tink.Error{type: :network_error, message: "Connection failed"}
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Creates an error from an HTTP response.

  ## Examples

      iex> Tink.Error.from_response(400, %{"errorCode" => "INVALID_REQUEST"})
      %Tink.Error{type: :api_error, status: 400, error_code: "INVALID_REQUEST"}
  """
  @spec from_response(integer(), map() | String.t()) :: t()
  def from_response(status, body) when is_map(body) do
    %__MODULE__{
      type: error_type_from_status(status),
      message: extract_message(body),
      status: status,
      error_code: Map.get(body, "errorCode") || Map.get(body, "error"),
      error_details: body,
      request_id: Map.get(body, "requestId")
    }
  end

  def from_response(status, body) when is_binary(body) do
    %__MODULE__{
      type: error_type_from_status(status),
      message: body,
      status: status
    }
  end

  def from_response(status, _body) do
    %__MODULE__{
      type: error_type_from_status(status),
      message: "HTTP #{status}",
      status: status
    }
  end

  @doc """
  Creates an error from an HTTP client error.

  ## Examples

      iex> Tink.Error.from_http_error(%{type: :timeout, reason: "Request timed out"})
      %Tink.Error{type: :timeout, message: "Request timed out"}
  """
  @spec from_http_error(map() | term()) :: t()
  def from_http_error(%{type: type, reason: reason}) do
    %__MODULE__{
      type: normalize_error_type(type),
      message: to_string(reason),
      original_error: reason
    }
  end

  def from_http_error(error) do
    %__MODULE__{
      type: :unknown,
      message: inspect(error),
      original_error: error
    }
  end

  @doc """
  Checks if an error is retryable.

  ## Examples

      iex> error = %Tink.Error{type: :network_error, message: ""}
      iex> Tink.Error.retryable?(error)
      true

      iex> error = %Tink.Error{type: :validation_error, message: ""}
      iex> Tink.Error.retryable?(error)
      false
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{type: type, status: status}) do
    retryable_type?(type) or retryable_status?(status)
  end

  @doc """
  Returns a human-readable error message.

  ## Examples

      iex> error = Tink.Error.from_response(429, %{"errorMessage" => "Rate limit exceeded"})
      iex> Tink.Error.format(error)
      "[429] Rate limit exceeded (RATE_LIMIT_ERROR)"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = error) do
    # Build prefix (status), then message, then suffix (error_code)
    prefix = if error.status, do: "[#{error.status}] ", else: ""
    suffix = if error.error_code, do: " (#{error.error_code})", else: ""
    "#{prefix}#{error.message}#{suffix}"
  end

  # Private Functions

  defp error_type_from_status(401), do: :authentication_error
  defp error_type_from_status(429), do: :rate_limit_error
  defp error_type_from_status(400), do: :validation_error
  defp error_type_from_status(status) when status in 401..499, do: :api_error
  defp error_type_from_status(status) when status in 500..599, do: :api_error
  defp error_type_from_status(_), do: :unknown

  defp normalize_error_type(:timeout), do: :timeout
  defp normalize_error_type(:network_error), do: :network_error
  defp normalize_error_type(:decode_error), do: :decode_error
  defp normalize_error_type(_), do: :unknown

  defp extract_message(%{"errorMessage" => message}) when is_binary(message), do: message
  defp extract_message(%{"error_description" => desc}) when is_binary(desc), do: desc
  defp extract_message(%{"message" => message}) when is_binary(message), do: message
  defp extract_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_message(_), do: "Unknown error"

  defp retryable_type?(type), do: type in [:network_error, :timeout]

  defp retryable_status?(status), do: status in [408, 429, 500, 502, 503, 504]

  defimpl String.Chars do
    def to_string(error), do: Tink.Error.format(error)
  end
end
