# Balance Check

`Tink.BalanceCheck` provides real-time balance verification for a user's
bank account. Use it to confirm sufficient funds before initiating a payment
or direct debit.

## Overview

Balance Check retrieves live balance data directly from the user's bank via
the Tink Link consent flow. It is typically used at the point of a transaction
to reduce failed payment rates.

## Starting a Session

```elixir
{:ok, session} = Tink.BalanceCheck.create_session(client,
  user_id:      "user_123",
  redirect_uri: "https://yourapp.com/callback",
  market:       "SE"
)

# Redirect the user to:
session.url
```

## Retrieving Balance

After the user completes the consent flow:

```elixir
{:ok, report} = Tink.BalanceCheck.get_report(client, session.id)

IO.inspect(report.balance_amount)    # Decimal — e.g. #Decimal<1523.50>
IO.inspect(report.balance_currency)  # "SEK"
IO.inspect(report.available_amount)  # Funds available for spending
```

## Checking Sufficient Funds

```elixir
required = Decimal.new("500.00")

case Tink.BalanceCheck.get_report(client, session.id) do
  {:ok, %{available_amount: available}} when available >= required ->
    initiate_payment()

  {:ok, %{available_amount: available}} ->
    {:error, :insufficient_funds, available}

  {:error, err} ->
    {:error, err}
end
```

## Consent Link

Build a consent update URL to refresh balance data without a full re-auth:

```elixir
{:ok, link} = Tink.BalanceCheck.build_consent_update_link(client, session.id)
# Redirect user to link.url for silent refresh
```

## Report Fields

| Field | Description |
|---|---|
| `balance_amount` | Current account balance as `Decimal` |
| `available_amount` | Spendable balance (excludes pending debits) |
| `balance_currency` | ISO 4217 currency code |
| `account_id` | Tink account identifier |
| `refreshed_at` | Timestamp of the balance fetch from the bank |
