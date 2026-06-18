defmodule Tink.Error do
  @moduledoc """
  Structured error returned by all Tink API functions.

  ## Fields

  - `:status` — HTTP status code (e.g. 401, 429). `nil` for network errors.
  - `:code` — Tink error code string (e.g. `"AUTHENTICATION_ERROR"`, `"NOT_FOUND"`)
  - `:message` — Human-readable error message
  - `:request_id` — Value of `X-Tink-Request-ID` response header — include this
    when reporting issues to Tink support
  - `:details` — Raw decoded response body for inspection

  ## Common error codes (from Tink docs)

  | Status | Code | Meaning |
  |--------|------|---------|
  | 400 | `BAD_REQUEST` | Malformed request body or params |
  | 401 | `AUTHENTICATION_ERROR` | Missing or invalid credentials |
  | 401 | `UNAUTHORIZED` | Token expired or revoked |
  | 403 | `FORBIDDEN` | Missing required scope |
  | 404 | `NOT_FOUND` | Resource does not exist |
  | 409 | `CONFLICT` | Resource already exists |
  | 422 | `UNPROCESSABLE_ENTITY` | Valid request but business logic rejection |
  | 429 | `TOO_MANY_REQUESTS` | Rate limit exceeded |
  | 500 | `INTERNAL_SERVER_ERROR` | Tink server error |
  | 503 | `SERVICE_UNAVAILABLE` | Tink service temporarily unavailable |
  | `nil` | `NETWORK_ERROR` | Connection / timeout failure |
  | `nil` | `DECODE_ERROR` | Invalid JSON in response body |

  ## Pattern matching

      case Tink.Accounts.list(client) do
        {:ok, accounts}                                      -> handle(accounts)
        {:error, %Tink.Error{status: 401}}                  -> refresh_and_retry()
        {:error, %Tink.Error{status: 403, code: code}}      -> handle_missing_scope(code)
        {:error, %Tink.Error{status: 429}}                  -> back_off_and_retry()
        {:error, %Tink.Error{status: nil, code: "NETWORK_ERROR"}} -> handle_network_failure()
        {:error, %Tink.Error{request_id: rid} = err}        ->
          Logger.error("Tink error request_id=\#{rid}: \#{Exception.message(err)}")
      end

  """

  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          code: String.t() | nil,
          message: String.t(),
          request_id: String.t() | nil,
          details: map() | nil
        }

  defexception [:status, :code, :message, :request_id, :details]

  @impl true
  def message(%__MODULE__{status: s, code: c, message: m}) do
    "[#{s || "?"}] #{c || "UNKNOWN"}: #{m}"
  end

  @doc """
  Build a structured error from an HTTP response.

  Tries the following keys in order to find the error code:
  `errorCode`, `error`, `code`

  Tries the following keys for the message:
  `errorMessage`, `error_description`, `message`
  """
  @spec from_response(non_neg_integer(), map(), String.t() | nil) :: t()
  def from_response(status, body, request_id \\ nil) when is_map(body) do
    %__MODULE__{
      status: status,
      code: body["errorCode"] || body["error"] || body["code"],
      message:
        body["errorMessage"] || body["error_description"] || body["message"] || "Unknown error",
      request_id: request_id,
      details: body
    }
  end

  @doc "Build a network-level error (no HTTP response received)."
  @spec network(String.t()) :: t()
  def network(reason) when is_binary(reason) do
    %__MODULE__{status: nil, code: "NETWORK_ERROR", message: reason}
  end

  @doc "Build a JSON decode error."
  @spec decode(String.t()) :: t()
  def decode(reason) when is_binary(reason) do
    %__MODULE__{status: nil, code: "DECODE_ERROR", message: reason}
  end

  @doc "Returns true if the error is retryable (429, 503, or network failure)."
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{status: s}) when s in [429, 503], do: true
  def retryable?(%__MODULE__{status: nil}), do: true
  def retryable?(_), do: false

  @doc "Returns true if the error is an authentication/authorization error."
  @spec auth_error?(t()) :: boolean()
  def auth_error?(%__MODULE__{status: s}) when s in [401, 403], do: true
  def auth_error?(_), do: false

  @doc "Returns true if the resource was not found."
  @spec not_found?(t()) :: boolean()
  def not_found?(%__MODULE__{status: 404}), do: true
  def not_found?(_), do: false
end
