# Tink

[![Hex.pm](https://img.shields.io/hexpm/v/tink.svg)](https://hex.pm/packages/tink)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/tink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A production-ready Elixir client for the [Tink open banking API](https://docs.tink.com).

Tink provides comprehensive access to Tink's full product suite — account
aggregation, transaction data, financial insights, account and income
verification — with built-in retry logic, optional caching, and optional
rate limiting.

## Features

- Full coverage of the Tink REST API
- OAuth 2.0 authentication (client credentials + authorization code)
- Automatic retry with exponential backoff and jitter
- Optional response caching via [Cachex](https://hex.pm/packages/cachex)
- Optional rate limiting via [Hammer](https://hex.pm/packages/hammer) 7.x
- Webhook signature verification (constant-time HMAC)
- Telemetry events for all HTTP requests, cache, and rate limit operations
- Strict TLS in production; zero runtime dependencies on `Mix`

## Installation

```elixir
# mix.exs
def deps do
  [
    {:tink, "~> 0.1"},

    # Optional — enable caching
    {:cachex, "~> 4.1"},

    # Optional — enable rate limiting
    {:hammer, "~> 7.2"}
  ]
end
```

## Quick Start

```elixir
# 1. Configure credentials (config/runtime.exs)
config :tink,
  client_id:     System.fetch_env!("TINK_CLIENT_ID"),
  client_secret: System.fetch_env!("TINK_CLIENT_SECRET")

# 2. Build a client
{:ok, client} = Tink.Client.new(
  client_id:     "your_client_id",
  client_secret: "your_client_secret"
)

# 3. Authenticate
{:ok, token} = Tink.Auth.client_credentials(client,
  scope: "accounts:read,transactions:read"
)
client = Tink.Client.with_token(client, token)

# 4. Call the API
{:ok, accounts} = Tink.Accounts.list(client)
```

## Products Covered

| Module | Description |
|---|---|
| `Tink.Accounts` | Bank account data and balances |
| `Tink.Transactions` | Full transaction history |
| `Tink.TransactionsOneTimeAccess` | Single-fetch transaction consent |
| `Tink.TransactionsContinuousAccess` | Ongoing transaction sync |
| `Tink.AccountCheck` | Bank account ownership verification |
| `Tink.BalanceCheck` | Real-time balance verification |
| `Tink.BusinessAccountCheck` | Business account ownership verification |
| `Tink.IncomeCheck` | Income stream analysis and PDF reports |
| `Tink.ExpenseCheck` | Spending categorisation and analysis |
| `Tink.RiskInsights` | Risk scoring and anomaly signals |
| `Tink.RiskCategorisation` | Transaction-level risk categories |
| `Tink.Investments` | Investment accounts and holdings |
| `Tink.Loans` | Loan and mortgage accounts |
| `Tink.Budgets` | User budget creation and tracking |
| `Tink.CashFlow` | Cash flow analysis |
| `Tink.FinancialCalendar` | Upcoming financial events |
| `Tink.Statistics` | Aggregated financial statistics |
| `Tink.Categories` | Tink transaction categories |
| `Tink.Users` | Tink user management |
| `Tink.Providers` | Bank provider metadata |
| `Tink.Link` | Tink Link URL generation |
| `Tink.Connectivity` | Provider connectivity checks |

## Configuration

```elixir
config :tink,
  client_id:            System.get_env("TINK_CLIENT_ID"),
  client_secret:        System.get_env("TINK_CLIENT_SECRET"),
  base_url:             "https://api.tink.com",  # default
  timeout:              30_000,                   # ms
  max_retries:          3,
  enable_rate_limiting: true,
  cache: [
    enabled:  true,
    max_size: 1_000
  ]
```

See the [Configuration guide](guides/configuration.md) for the full reference.

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/tink).

- [Getting Started](guides/getting-started.md)
- [Authentication](guides/authentication.md)
- [Configuration](guides/configuration.md)
- [Error Handling](guides/advanced/error-handling.md)
- [Caching](guides/advanced/caching.md)
- [Rate Limiting](guides/advanced/rate-limiting.md)
- [Telemetry](guides/advanced/telemetry.md)
- [Webhooks](guides/advanced/webhooks.md)
- [Testing](guides/advanced/testing.md)

## License

MIT — see [LICENSE](LICENSE).