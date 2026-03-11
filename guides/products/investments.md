# Investments

`Tink.Investments` provides read access to a user's investment accounts,
portfolios, and individual holdings across connected brokers and banks.

## Listing Investment Accounts

```elixir
{:ok, accounts} = Tink.Investments.list_accounts(client)

Enum.each(accounts, fn acc ->
  IO.puts("#{acc.name}  #{acc.type}  #{acc.total_value} #{acc.currency}")
end)
```

## Fetching Holdings

```elixir
{:ok, holdings} = Tink.Investments.get_holdings(client, account_id)

Enum.each(holdings, fn h ->
  IO.puts("""
  #{h.name} (#{h.ticker})
  Quantity: #{h.quantity}
  Value:    #{h.market_value} #{h.currency}
  Return:   #{h.profit_loss_percent}%
  """)
end)
```

## Account Fields

| Field | Description |
|---|---|
| `id` | Tink account identifier |
| `name` | Account display name |
| `type` | `"ISA"`, `"SIPP"`, `"GIA"`, `"PENSION"`, etc. |
| `total_value` | Current portfolio value as `Decimal` |
| `currency` | ISO 4217 currency code |
| `provider_name` | Broker or bank name |

## Holding Fields

| Field | Description |
|---|---|
| `id` | Holding identifier |
| `name` | Security name |
| `ticker` | Ticker symbol |
| `isin` | ISIN code |
| `quantity` | Number of units held |
| `purchase_price` | Average purchase price as `Decimal` |
| `market_value` | Current market value as `Decimal` |
| `profit_loss` | Absolute profit/loss as `Decimal` |
| `profit_loss_percent` | Percentage return |

## Portfolio Summary

```elixir
{:ok, accounts} = Tink.Investments.list_accounts(client)

total = accounts
  |> Enum.map(& &1.total_value)
  |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

IO.puts("Total portfolio value: #{total}")
```
