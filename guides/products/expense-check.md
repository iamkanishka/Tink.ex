# Expense Check

`Tink.ExpenseCheck` categorises and analyses a user's spending patterns from
their transaction history. Use it for affordability assessments, budget
recommendations, or financial health scoring.

## Overview

Expense Check fetches up to 12 months of transactions from the user's bank,
applies Tink's categorisation engine, and returns a structured breakdown of
spending by category.

## Starting a Session

```elixir
{:ok, session} = Tink.ExpenseCheck.create_session(client,
  user_id:      "user_123",
  redirect_uri: "https://yourapp.com/callback",
  market:       "SE",
  months_back:  3
)

# Redirect the user to:
session.url
```

## Retrieving the Report

```elixir
{:ok, report} = Tink.ExpenseCheck.get_report(client, session.id)

Enum.each(report.expense_categories, fn cat ->
  IO.puts("#{cat.name}: #{cat.total_amount} #{cat.currency} (#{cat.transaction_count} txns)")
end)
```

## Category Summary

```elixir
# Highest spending category
top = Enum.max_by(report.expense_categories, & &1.total_amount)
IO.puts("Top expense: #{top.name} — #{top.total_amount} #{top.currency}")
```

## Expense Category Fields

| Field | Description |
|---|---|
| `name` | Category name (e.g. `"FOOD_AND_DRINK"`) |
| `total_amount` | Total spent in the period as `Decimal` |
| `currency` | ISO 4217 currency code |
| `transaction_count` | Number of transactions in this category |
| `monthly_average` | Average monthly spend as `Decimal` |

## Report-Level Fields

| Field | Description |
|---|---|
| `total_expenses` | Aggregate spend across all categories |
| `period_from` | Start of analysis window |
| `period_to` | End of analysis window |
| `currency` | Currency of the totals |
| `created_at` | Report generation timestamp |

## Tink Category Types

Common categories returned by Expense Check:

- `FOOD_AND_DRINK`
- `TRANSPORT`
- `HOUSING`
- `ENTERTAINMENT`
- `HEALTH_AND_WELLNESS`
- `SHOPPING`
- `UTILITIES`
- `SAVINGS_AND_INVESTMENTS`
- `TRANSFERS`
- `UNCATEGORIZED`
