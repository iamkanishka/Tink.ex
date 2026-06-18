defmodule Tink.Webhooks do
  @moduledoc """
  Webhook endpoint registration and management.

  Requires `webhook-endpoints` scope.

  ## Setup

      {:ok, client} = Tink.Auth.client_credentials(scope: "webhook-endpoints")

      {:ok, endpoint} = Tink.Webhooks.create(client, %{
        "url"           => "https://yourapp.com/tink/events",
        "enabledEvents" => [
          "account.updated",
          "credentials.updated",
          "transaction.updated",
          "consent.revoked"
        ]
      })

  ## Handling events

  See `Tink.WebhookHandler` for event dispatch and `Tink.WebhookVerifier` for signature verification.
  """

  alias Tink.{Client, Error}

  @doc "Create a webhook endpoint. Requires `webhook-endpoints`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/events/v2/webhook-endpoints", params)
  end

  @doc "List all registered webhook endpoints. Requires `webhook-endpoints`."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/events/v2/webhook-endpoints")

  @doc "Get a webhook endpoint by ID. Requires `webhook-endpoints`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, endpoint_id) when is_binary(endpoint_id) do
    Client.get(client, "/events/v2/webhook-endpoints/#{endpoint_id}")
  end

  @doc "Update a webhook endpoint. Requires `webhook-endpoints`."
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, endpoint_id, %{} = params) when is_binary(endpoint_id) do
    Client.put(client, "/events/v2/webhook-endpoints/#{endpoint_id}", params)
  end

  @doc "Delete a webhook endpoint. Requires `webhook-endpoints`."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{} = client, endpoint_id) when is_binary(endpoint_id) do
    case Client.delete(client, "/events/v2/webhook-endpoints/#{endpoint_id}") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end

defmodule Tink.WebhookVerifier do
  @moduledoc """
  Constant-time HMAC-SHA256 signature verification for incoming Tink webhooks.

  Tink signs payloads with the secret configured in your app settings. The
  signature arrives in the `X-Tink-Signature` request header as a lowercase
  hex digest.

  ## Phoenix / Plug usage

      defmodule MyAppWeb.TinkWebhookController do
        use MyAppWeb, :controller

        def handle(conn, _params) do
          with {:ok, body, conn} <- Plug.Conn.read_body(conn),
               [sig | _]         <- Plug.Conn.get_req_header(conn, "x-tink-signature"),
               :ok               <- Tink.WebhookVerifier.verify_with_config(body, sig),
               {:ok, event}      <- Jason.decode(body) do
            Tink.WebhookHandler.dispatch(event)
            send_resp(conn, 200, "ok")
          else
            [] -> send_resp(conn, 401, "missing signature")
            {:error, reason} -> send_resp(conn, 401, reason)
          end
        end
      end

  """

  alias Plug.Conn
  alias Tink.Config

  @doc "Verify a raw body against a signature using the provided secret."
  @spec verify(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def verify(body, signature, secret)
      when is_binary(body) and is_binary(signature) and is_binary(secret) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, body)
      |> Base.encode16(case: :lower)

    if secure_compare(expected, signature) do
      :ok
    else
      {:error, "Invalid webhook signature"}
    end
  end

  # Constant-time binary comparison with no external dependency.
  #
  # `Plug.Crypto.secure_compare/2` is the idiomatic choice here, but it is
  # NOT declared as a dependency of this package (and shouldn't be — pulling
  # in Plug/Plug.Crypto just for this one comparison would be an unnecessary
  # dependency for non-Phoenix consumers, e.g. an Oban worker or CLI tool
  # processing webhooks outside of a web app). We implement it ourselves
  # instead, using `:crypto.hash_equals/2` (OTP 25+) when available and
  # falling back to a manual XOR-accumulator comparison on older OTP
  # releases that Elixir 1.14 still supports (OTP 23/24).
  #
  # Note `:crypto.hash_equals/2` raises on length mismatch by design (per
  # the Erlang/OTP maintainers — see erlang/otp#4750), so we check lengths
  # up front rather than let that crash propagate; differing lengths are
  # just as invalid as differing content, so this is also constant-time
  # with respect to content given equal lengths, which is what we need to
  # prevent length being trivially observable to begin with (truncating
  # one side wouldn't help an attacker since the signature length is fixed
  # by the algorithm anyway).
  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  if Code.ensure_loaded?(:crypto) and function_exported?(:crypto, :hash_equals, 2) do
    defp secure_compare(a, b), do: :crypto.hash_equals(a, b)
  else
    defp secure_compare(a, b) do
      a
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(b))
      |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
      |> Kernel.==(0)
    end
  end

  @doc "Verify using the webhook secret from application config."
  @spec verify_with_config(String.t(), String.t()) :: :ok | {:error, String.t()}
  def verify_with_config(body, signature)
      when is_binary(body) and is_binary(signature) do
    case Config.webhook_secret() do
      nil -> {:error, "No webhook secret configured — set config :tink, :webhook_secret"}
      secret -> verify(body, signature, secret)
    end
  end

  @doc "Verify an incoming Plug.Conn webhook request."
  @spec verify_plug(Conn.t(), String.t() | nil) :: :ok | {:error, String.t()}
  def verify_plug(conn, secret \\ nil) do
    effective_secret = secret || Config.webhook_secret()

    case effective_secret do
      nil ->
        {:error, "No webhook secret configured"}

      s ->
        with {:ok, body, _conn} <- Conn.read_body(conn),
             [sig | _] <- Conn.get_req_header(conn, "x-tink-signature"),
             :ok <- verify(body, sig, s) do
          :ok
        else
          [] -> {:error, "Missing X-Tink-Signature header"}
          {:error, _} = e -> e
        end
    end
  end
end

defmodule Tink.WebhookHandler do
  @moduledoc """
  Event-driven webhook handler with a per-event-type handler registry.

  Handlers are registered at startup and called when a matching event is
  dispatched. Exceptions in handlers are caught and logged without crashing
  the dispatcher.

  ## Setup

      # In your Application.start/2:
      Tink.WebhookHandler.handle("account.updated", fn event ->
        MyApp.Accounts.sync(event["content"])
      end)

      Tink.WebhookHandler.handle("transaction.created", fn event ->
        MyApp.Transactions.process(event["content"])
      end)

      Tink.WebhookHandler.handle("consent.revoked", fn event ->
        MyApp.Consents.on_revoked(event["content"])
      end)

  ## Dispatching

      # In your webhook controller after verifying the signature:
      {:ok, event} = Jason.decode(raw_body)
      Tink.WebhookHandler.dispatch(event)

  ## Known event types

      Tink.WebhookHandler.known_events()
      # => ["account.updated", "credentials.updated", ...]

  """

  require Logger

  # ── Known event types ─────────────────────────────────────────────────────────

  @known_events [
    "account.updated",
    "credentials.updated",
    "credentials.authentication-error",
    "transaction.updated",
    "transaction.created",
    "refresh.finished",
    "consent.created",
    "consent.updated",
    "consent.revoked",
    "payment.updated",
    "payment.created",
    "balance.updated"
  ]

  # ── Dispatcher GenServer ──────────────────────────────────────────────────────

  defmodule Dispatcher do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
    end

    @impl true
    def init(_), do: {:ok, %{}}

    @impl true
    def handle_call({:register, event, fun}, _from, state) do
      handlers = Map.get(state, event, [])
      {:reply, :ok, Map.put(state, event, [fun | handlers])}
    end

    @impl true
    def handle_call({:get, event}, _from, state) do
      {:reply, Map.get(state, event, []), state}
    end

    @impl true
    def handle_call(:all, _from, state) do
      {:reply, state, state}
    end

    @impl true
    def handle_call({:clear, event}, _from, state) do
      {:reply, :ok, Map.delete(state, event)}
    end
  end

  # ── Public API ────────────────────────────────────────────────────────────────

  @doc "Register a handler function for an event type. Can be called multiple times to add multiple handlers."
  @spec handle(String.t(), (map() -> any())) :: :ok
  def handle(event_type, fun) when is_binary(event_type) and is_function(fun, 1) do
    GenServer.call(Dispatcher, {:register, event_type, fun})
  end

  @doc """
  Dispatch a parsed webhook event map to all registered handlers.

  Returns `:ok` even if no handlers are registered.
  Handler exceptions are caught and logged.
  """
  @spec dispatch(map()) :: :ok
  def dispatch(%{"event" => event_type} = payload) do
    handlers = GenServer.call(Dispatcher, {:get, event_type})

    Enum.each(handlers, fn handler ->
      try do
        handler.(payload)
      rescue
        e ->
          Logger.error(
            "[Tink.WebhookHandler] Handler raised for event #{inspect(event_type)}: " <>
              Exception.message(e) <> "\n" <> Exception.format_stacktrace(__STACKTRACE__)
          )
      catch
        kind, value ->
          Logger.error(
            "[Tink.WebhookHandler] Handler threw #{kind} for event #{inspect(event_type)}: " <>
              inspect(value)
          )
      end
    end)

    :ok
  end

  def dispatch(payload) when is_map(payload) do
    Logger.warning("[Tink.WebhookHandler] Received event without 'event' key: #{inspect(payload)}")
    :ok
  end

  @doc "Get all registered handlers (map of event_type => [handler_fn])."
  @spec get_handlers() :: map()
  def get_handlers, do: GenServer.call(Dispatcher, :all)

  @doc "Get handlers for a specific event type."
  @spec get_handlers(String.t()) :: list()
  def get_handlers(event_type) when is_binary(event_type) do
    GenServer.call(Dispatcher, {:get, event_type})
  end

  @doc "Clear all handlers for an event type. Useful in tests."
  @spec clear_handlers(String.t()) :: :ok
  def clear_handlers(event_type) when is_binary(event_type) do
    GenServer.call(Dispatcher, {:clear, event_type})
  end

  @doc "List all known Tink webhook event types."
  @spec known_events() :: [String.t()]
  def known_events, do: @known_events
end
