# Authentication

This guide covers OAuth 2.0 token lifetimes, mutual TLS (mTLS), and
TLS/certificate rotation requirements as documented by Tink.

## OAuth 2.0 token lifetimes

| Grant type | Token lifetime | SDK function |
|---|---|---|
| client_credentials | **1800 seconds** (30 min) | Tink.Auth.client_credentials/1 |
| authorization_code | **7200 seconds** (2 hours) | Tink.Auth.user_client/2 |

Both are documented defaults — if Tink's response includes an explicit
expires_in, the SDK uses that value instead.

Neither flow returns a refresh_token by default. To get a new token,
re-run the same grant flow. If your integration does receive a
refresh_token (e.g. via mTLS or a non-standard flow), it's captured on
client.refresh_token and can be used with Tink.Auth.refresh/3.

## Checking token freshness

elixir
# Proactive refresh — check before making a batch of calls
if Tink.AuthToken.should_refresh?(client) do
  {:ok, client} = Tink.Auth.client_credentials(scope: client.scope)
end

# Inspect remaining lifetime
Tink.AuthToken.seconds_until_expiry(client)   # => 1432
Tink.AuthToken.expiry_summary(client)         # => "expires in 23 min"


## Scope checking before calling an endpoint

elixir
required = ["accounts:read", "transactions:read"]

if Tink.AuthToken.has_all_scopes?(client, required) do
  Tink.Transactions.list(client)
else
  missing = Tink.AuthToken.missing_scopes(client, required)
  {:error, "Missing scopes: #{Enum.join(missing, ", ")}"}
end


## Mutual TLS (mTLS)

Tink supports mTLS as an alternative OAuth client authentication method
(RFC 8705). Use Tink.HTTP.MutualTLS instead of the default Tink.HTTP.Finch
adapter.

### Configuration

elixir
# config/runtime.exs
config :tink,
  http_adapter: Tink.HTTP.MutualTLS,
  mtls: [
    cert_file: System.get_env("TINK_CLIENT_CERT_PATH"),
    key_file:  System.get_env("TINK_CLIENT_KEY_PATH")
  ]


Or with inline PEM strings:

elixir
config :tink,
  http_adapter: Tink.HTTP.MutualTLS,
  mtls: [
    cert_pem: System.get_env("TINK_CLIENT_CERT_PEM"),
    key_pem:  System.get_env("TINK_CLIENT_KEY_PEM")
  ]


### Starting the mTLS Finch pool

Add Tink.HTTP.MutualTLS.child_spec() to your application's supervisor tree
alongside (or instead of) the default pool started by Tink.Application:

elixir
children = [
  Tink.HTTP.MutualTLS.child_spec(),
  # ... your other children
]


## TLS version requirements

- **Current minimum:** TLS 1.2
- **TLS 1.2 will be discontinued 31 December 2027** — Tink will require TLS 1.3
  from that date. Tink.HTTP.MutualTLS already negotiates TLS 1.3 first with
  TLS 1.2 fallback (versions: [:"tlsv1.3", :"tlsv1.2"]).
- The default Tink.HTTP.Finch adapter uses your OTP's default TLS settings,
  which support both versions on modern OTP releases (25+).

## CA certificate rotation

Tink's API server certificate is currently issued under **DigiCert Global
Root G2** (RSA SHA-256).

**On 17 September 2026**, Tink will rotate to **Amazon Root CA 3**
(EC prime256v1). If your application:

- Uses the system CA trust store (default) — **no action needed**, both roots
  are widely trusted.
- Uses certificate pinning or a custom CA bundle — **add Amazon Root CA 3 to
  your trust store before 17 September 2026**, and keep DigiCert Global Root
  G2 until the rotation completes.

elixir
# If pinning via mtls ca_pem, include both roots during the transition window:
config :tink,
  mtls: [
    cert_file: "...",
    key_file:  "...",
    ca_pem: digicert_g2_pem <> amazon_root_ca3_pem
  ]


## Error codes related to authentication

| Status | Code | Meaning | Action |
|---|---|---|---|
| 401 | AUTHENTICATION_ERROR | Invalid client_id/client_secret | Check credentials |
| 401 | UNAUTHORIZED | Token expired or revoked | Re-authenticate |
| 403 | FORBIDDEN | Token lacks required scope | Request broader scope |

elixir
case Tink.Accounts.list(client) do
  {:error, %Tink.Error{} = err} ->
    cond do
      Tink.Error.auth_error?(err) and err.status == 401 ->
        {:ok, new_client} = Tink.Auth.client_credentials(scope: client.scope)
        Tink.Accounts.list(new_client)

      Tink.Error.auth_error?(err) and err.status == 403 ->
        Logger.error("Missing scope — request: #{err.message}")

      true ->
        {:error, err}
    end

  ok -> ok
end

