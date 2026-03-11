# Webhooks

Tink provides `Tink.WebhookHandler` and `Tink.WebhookVerifier` to receive
and process real-time event notifications from the Tink API.

## Supported Events

| Event type | Trigger |
|---|---|
| `credentials.created` | A new bank credential is linked |
| `credentials.updated` | A credential is refreshed or modified |
| `credentials.deleted` | A credential is unlinked |
| `account.updated` | Account balance or metadata changes |
| `transactions.updated` | New transactions are available |
| `transfer.updated` | Payment status changes |

## Registering Handlers

Handlers are registered at runtime using an ETS-backed registry — safe for
concurrent registration across processes:

```elixir
Tink.WebhookHandler.register(:credentials_created, fn payload ->
  Logger.info("New credential: #{inspect(payload)}")
  MyApp.Credentials.on_created(payload)
end)

Tink.WebhookHandler.register(:transactions_updated, fn payload ->
  MyApp.Transactions.sync(payload["credentialId"])
end)
```

## Processing Incoming Webhooks

In your Phoenix controller (or Plug):

```elixir
defmodule MyAppWeb.TinkWebhookController do
  use MyAppWeb, :controller

  def receive(conn, _params) do
    raw_body   = conn.assigns[:raw_body]   # captured by a Plug before parsing
    signature  = get_req_header(conn, "x-tink-signature") |> List.first()

    case Tink.WebhookHandler.process(raw_body, signature) do
      :ok ->
        send_resp(conn, 200, "ok")

      {:error, :invalid_signature} ->
        send_resp(conn, 401, "invalid signature")

      {:error, :test_webhook} ->
        # Test webhooks from the Tink console are handled but not dispatched
        send_resp(conn, 200, "test acknowledged")
    end
  end
end
```

## Signature Verification

`Tink.WebhookVerifier` uses constant-time comparison via `:crypto.hash_equals/2`
to guard against timing attacks. The webhook secret is configured via:

```elixir
config :tink,
  webhook_secret: System.get_env("TINK_WEBHOOK_SECRET")
```

You can also verify manually:

```elixir
case Tink.WebhookVerifier.verify(raw_body, signature) do
  :ok              -> process(raw_body)
  {:error, reason} -> Logger.error("Bad webhook: #{reason}")
end
```

## Capturing the Raw Body in Phoenix

Plug parses the body before it reaches your controller. Capture it first:

```elixir
# lib/my_app_web/plugs/raw_body.ex
defmodule MyAppWeb.Plugs.RawBody do
  def init(opts), do: opts

  def call(%{request_path: "/webhooks/tink"} = conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Plug.Conn.assign(conn, :raw_body, body)
  end

  def call(conn, _opts), do: conn
end
```

Add it to your endpoint before the body parsers:

```elixir
# lib/my_app_web/endpoint.ex
plug MyAppWeb.Plugs.RawBody
plug Plug.Parsers, parsers: [:urlencoded, :json], json_decoder: Jason
```

## Unregistering Handlers

```elixir
Tink.WebhookHandler.unregister(:credentials_created, handler_ref)
```
