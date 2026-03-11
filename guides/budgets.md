# Budgets

`Tink.Budgets` allows you to create and manage spending budgets for Tink
users. Budgets track spending against a target amount within a category and
time period.

## Listing Budgets

```elixir
{:ok, budgets} = Tink.Budgets.list_budgets(client)

Enum.each(budgets, fn b ->
  IO.puts("#{b.name}: #{b.spent}/#{b.amount} #{b.currency} (#{b.period})")
end)
```

## Fetching a Single Budget

```elixir
{:ok, budget} = Tink.Budgets.get_budget(client, budget_id)

IO.inspect(budget.spent)       # Amount spent so far this period
IO.inspect(budget.remaining)   # Amount remaining
IO.inspect(budget.status)      # :on_track | :at_risk | :exceeded
```

## Creating a Budget

```elixir
{:ok, budget} = Tink.Budgets.create_budget(client,
  name:          "Groceries",
  amount:        Decimal.new("400.00"),
  currency:      "GBP",
  category_type: "FOOD_AND_DRINK",
  period:        "MONTHLY"
)
```

## Updating a Budget

```elixir
{:ok, budget} = Tink.Budgets.update_budget(client, budget_id,
  amount: Decimal.new("450.00")
)
```

Updating a budget automatically invalidates the cached entry for that budget.

## Deleting a Budget

```elixir
:ok = Tink.Budgets.delete_budget(client, budget_id)
```

## Budget Fields

| Field | Description |
|---|---|
| `id` | Budget identifier |
| `name` | Budget display name |
| `amount` | Budget target amount as `Decimal` |
| `currency` | ISO 4217 currency code |
| `spent` | Amount spent this period as `Decimal` |
| `remaining` | Budget target minus spent |
| `period` | `"WEEKLY"`, `"MONTHLY"`, or `"YEARLY"` |
| `category_type` | Tink category this budget tracks |
| `status` | `:on_track`, `:at_risk`, or `:exceeded` |
| `created_at` | Creation timestamp |

## Budget Status Logic

- `:on_track` — spent is less than 80% of the target
- `:at_risk` — spent is 80–100% of the target
- `:exceeded` — spent has surpassed the target amount
