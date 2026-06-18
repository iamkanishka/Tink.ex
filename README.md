# Tink

[![Hex.pm](https://img.shields.io/hexpm/v/tink.svg)](https://hex.pm/packages/tink)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

A complete, production-grade Elixir client for the [Tink Open Banking
API](https://docs.tink.com). Covers data aggregation (accounts, transactions,
identities, investments, loans), enrichment (categories, recurring,
merchants, on-demand enrichment, sustainability), payments and VRP, risk
insights, income/expense checks, savings goals and other personal-finance
modules, connectivity/consents, webhooks, and more.

Built on `Req`/Finch, with typed errors, telemetry, client-side caching
(Cachex) and rate limiting (Hammer), and full test coverage against a mocked
HTTP adapter.

## Installation

Add `tink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tink, "~> 1.0"}
  ]
end
```

Documentation is published on [HexDocs](https://hexdocs.pm/tink).

## Configuration

```elixir
# config/config.exs
config :tink,
  client_id: System.get_env("TINK_CLIENT_ID"),
  client_secret: System.get_env("TINK_CLIENT_SECRET"),
  webhook_secret: System.get_env("TINK_WEBHOOK_SECRET")
```

See `config/config.exs` in this repo for the full set of options (base
URLs, timeouts, retries, cache, and rate-limit settings) and their defaults.

## Quick start

```elixir
# 1. Get an app-level access token (client_credentials grant)
{:ok, client} = Tink.Auth.client_credentials(scope: "accounts:read,transactions:read")

# 2. Use it to call the API
{:ok, accounts} = Tink.Accounts.list(client)

# 3. For end-user data, create a permanent user and an authorization grant,
#    then exchange the resulting code for a user-scoped token
{:ok, %{"code" => code}} =
  Tink.Auth.create_authorization(client, user_id: user_id, scope: "accounts:read")

{:ok, user_client} = Tink.Auth.user_client(code: code)
{:ok, transactions} = Tink.Transactions.list(user_client)
```

See the guides under `guides/advanced/` for authentication flows (including
mTLS), caching, error handling, and rate limiting.

## Status

This package targets Tink's documented API surface as of mid-2026. If you
notice an endpoint, scope, or behavior that's out of date, please open an
issue — Tink's docs are a single-page app that's not always crawlable, so
some details were cross-checked via cached search results rather than a
live fetch.

## License

Apache-2.0. See [LICENSE](LICENSE).
