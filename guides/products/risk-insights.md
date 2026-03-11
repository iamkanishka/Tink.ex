# Risk Insights

`Tink.RiskInsights` and `Tink.RiskCategorisation` provide transaction-level
risk scoring and categorisation signals. Use them to detect anomalous spending,
assess creditworthiness, or flag high-risk financial behaviour.

## Risk Insights

### Fetching Insights

```elixir
{:ok, insights} = Tink.RiskInsights.get(client, user_id: "user_123")

IO.inspect(insights.risk_score)        # 0.0–1.0
IO.inspect(insights.overdraft_events)  # count in last 90 days
IO.inspect(insights.income_stability)  # :high | :medium | :low
```

### Insight Fields

| Field | Description |
|---|---|
| `risk_score` | Composite risk score `0.0` (low) – `1.0` (high) |
| `overdraft_events` | Number of overdraft events in the analysis window |
| `income_stability` | `:high`, `:medium`, or `:low` |
| `average_balance` | Rolling 90-day average balance as `Decimal` |
| `balance_volatility` | Standard deviation of daily balances |
| `gambling_detected` | Boolean — gambling transactions present |
| `credit_usage` | Ratio of credit card spend to available credit |

## Risk Categorisation

`Tink.RiskCategorisation` provides raw category signals at the transaction
level, giving you the building blocks to construct custom risk models.

### Fetching Categorisations

```elixir
{:ok, report} = Tink.RiskCategorisation.get_report(client, session.id)

Enum.each(report.categories, fn cat ->
  IO.puts("#{cat.type}: #{cat.amount} — #{cat.signal}")
end)
```

### Category Signals

| Signal | Description |
|---|---|
| `GAMBLING` | Gambling platform transactions |
| `PAYDAY_LOAN` | High-interest short-term borrowing |
| `OVERDRAFT` | Transactions that triggered an overdraft |
| `IRREGULAR_INCOME` | Income with high variance |
| `LARGE_CASH_WITHDRAWAL` | ATM withdrawals above threshold |
| `FREQUENT_TRANSFERS` | Unusually high transfer frequency |

## Combining Insights and Categorisation

```elixir
with {:ok, insights}  <- Tink.RiskInsights.get(client, user_id: user_id),
     {:ok, report}    <- Tink.RiskCategorisation.get_report(client, session_id) do

  if insights.risk_score > 0.7 or report.gambling_transaction_count > 0 do
    {:decline, :high_risk}
  else
    {:approve, insights.risk_score}
  end
end
```
