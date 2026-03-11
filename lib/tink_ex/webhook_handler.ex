defmodule TinkEx.WebhookHandler do
  @moduledoc """
  Handler for Tink API webhooks.

  Tink sends webhooks for various events like:
  - User credentials updated
  - Transaction data refreshed
  - Account data changed
  - Credential errors

  ## Setup

  1. Configure webhook secret in your application:

      config :tink_ex,
        webhook_secret: System.get_env("TINK_WEBHOOK_SECRET")

  2. Create a webhook endpoint in your Phoenix app:

      defmodule MyAppWeb.TinkWebhookController do
        use MyAppWeb, :controller

        def handle(conn, params) do
          signature = get_req_header(conn, "x-tink-signature") |> List.first()
          body = conn.assigns.raw_body  # You need to capture raw body

          case TinkEx.WebhookHandler.handle_webhook(body, signature) do
            {:ok, event} ->
              # Process event
              process_webhook_event(event)
              send_resp(conn, 200, "OK")

            {:error, :invalid_signature} ->
              send_resp(conn, 401, "Invalid signature")

            {:error, reason} ->
              send_resp(conn, 400, "Bad request: #{reason}")
          end
        end
      end

  3. Register webhook handlers:

      TinkEx.WebhookHandler.register_handler(:credentials_updated, &handle_credentials_update/1)

  ## Webhook Events

  Tink sends the following event types:

  - `credentials.updated` - Credentials were updated
  - `credentials.refresh.succeeded` - Data refresh succeeded
  - `credentials.refresh.failed` - Data refresh failed
  - `provider_consents.created` - Consent was created
  - `provider_consents.revoked` - Consent was revoked

  ## Examples

      # Handle webhook in controller
      def webhook(conn, _params) do
        signature = get_req_header(conn, "x-tink-signature") |> List.first()
        body = conn.assigns.raw_body

        case TinkEx.WebhookHandler.handle_webhook(body, signature) do
          {:ok, event} ->
            MyApp.Webhooks.process(event)
            send_resp(conn, 200, "OK")

          {:error, :invalid_signature} ->
            send_resp(conn, 401, "Unauthorized")
        end
      end

      # Register event handlers
      TinkEx.WebhookHandler.register_handler(:credentials_updated, fn event ->
        # Update user's credential status
        Users.update_credential_status(event["userId"], :updated)
      end)

  ## Verification

  Webhooks are verified using HMAC-SHA256 signature.
  """

  require Logger

  alias TinkEx.{Config, WebhookVerifier}

  @type event_type ::
          :credentials_updated
          | :credentials_refresh_succeeded
          | :credentials_refresh_failed
          | :provider_consents_created
          | :provider_consents_revoked
          | :unknown

  @type event :: %{
          type: event_type(),
          data: map(),
          timestamp: DateTime.t(),
          raw: map()
        }

  @type handler_function :: (event() -> term())

  @doc """
  Handles an incoming webhook request.

  Verifies the signature and parses the webhook event.

  ## Parameters

    * `body` - Raw webhook request body (JSON string)
    * `signature` - Webhook signature from `X-Tink-Signature` header

  ## Returns

    * `{:ok, event}` - Successfully parsed and verified webhook
    * `{:error, :invalid_signature}` - Signature verification failed
    * `{:error, :invalid_payload}` - Failed to parse webhook body

  ## Examples

      {:ok, event} = TinkEx.WebhookHandler.handle_webhook(body, signature)
      #=> {:ok, %{type: :credentials_updated, data: %{...}}}
  """
  @spec handle_webhook(String.t(), String.t()) ::
          {:ok, event()} | {:error, atom()}
  def handle_webhook(body, signature) when is_binary(body) and is_binary(signature) do
    secret = Config.get(:webhook_secret)

    if is_nil(secret) do
      Logger.error("[TinkEx.WebhookHandler] Webhook secret not configured")
      {:error, :webhook_secret_not_configured}
    else
      with :ok <- WebhookVerifier.verify_signature(body, signature, secret),
           {:ok, payload} <- Jason.decode(body),
           {:ok, event} <- parse_event(payload) do
        emit_telemetry(event)
        notify_handlers(event)
        {:ok, event}
      else
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Registers a handler function for a specific event type.

  ## Parameters

    * `event_type` - Type of event to handle
    * `handler_fun` - Function to call when event is received

  ## Examples

      TinkEx.WebhookHandler.register_handler(:credentials_updated, fn event ->
        Logger.info("Credentials updated for user: #{event.data["userId"]}")
        MyApp.Users.sync_credentials(event.data["userId"])
      end)
  """
  @spec register_handler(event_type(), handler_function()) :: :ok
  def register_handler(event_type, handler_fun) when is_function(handler_fun, 1) do
    handlers = get_handlers()
    type_handlers = Map.get(handlers, event_type, [])
    updated_handlers = Map.put(handlers, event_type, [handler_fun | type_handlers])

    Application.put_env(:tink_ex, :webhook_handlers, updated_handlers)
    :ok
  end

  @doc """
  Unregisters all handlers for an event type.

  ## Examples

      TinkEx.WebhookHandler.unregister_handlers(:credentials_updated)
  """
  @spec unregister_handlers(event_type()) :: :ok
  def unregister_handlers(event_type) do
    handlers = get_handlers()
    updated_handlers = Map.delete(handlers, event_type)

    Application.put_env(:tink_ex, :webhook_handlers, updated_handlers)
    :ok
  end

  @doc """
  Gets all registered handlers.

  ## Examples

      handlers = TinkEx.WebhookHandler.get_handlers()
      #=> %{credentials_updated: [#Function<...>]}
  """
  @spec get_handlers() :: %{event_type() => [handler_function()]}
  def get_handlers do
    Application.get_env(:tink_ex, :webhook_handlers, %{})
  end

  # Private Functions

  defp parse_event(payload) when is_map(payload) do
    event_type = parse_event_type(payload["type"])

    event = %{
      type: event_type,
      data: payload["data"] || %{},
      timestamp: parse_timestamp(payload["timestamp"]),
      raw: payload
    }

    {:ok, event}
  rescue
    _ -> {:error, :invalid_payload}
  end

  defp parse_event_type("credentials.updated"), do: :credentials_updated
  defp parse_event_type("credentials.refresh.succeeded"), do: :credentials_refresh_succeeded
  defp parse_event_type("credentials.refresh.failed"), do: :credentials_refresh_failed
  defp parse_event_type("provider_consents.created"), do: :provider_consents_created
  defp parse_event_type("provider_consents.revoked"), do: :provider_consents_revoked
  defp parse_event_type(_), do: :unknown

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()

  defp notify_handlers(event) do
    handlers = get_handlers()
    event_handlers = Map.get(handlers, event.type, [])

    # Also notify wildcard handlers (if any)
    wildcard_handlers = Map.get(handlers, :all, [])

    all_handlers = event_handlers ++ wildcard_handlers

    Enum.each(all_handlers, fn handler ->
      try do
        handler.(event)
      rescue
        error ->
          Logger.error("""
          [TinkEx.WebhookHandler] Handler error
          Event: #{inspect(event.type)}
          Error: #{inspect(error)}
          """)
      end
    end)
  end

  defp emit_telemetry(event) do
    :telemetry.execute(
      [:tink_ex, :webhook, :received],
      %{},
      %{event_type: event.type, data: event.data}
    )
  end
end
