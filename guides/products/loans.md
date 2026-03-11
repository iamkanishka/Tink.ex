# Loans

`Tink.Loans` provides read access to a user's loan accounts, including
mortgages, personal loans, and credit facilities connected through Tink.

## Listing Loan Accounts

```elixir
{:ok, loans} = Tink.Loans.list_accounts(client)

Enum.each(loans, fn loan ->
  IO.puts("""
  #{loan.name}
  Type:       #{loan.type}
  Balance:    #{loan.balance} #{loan.currency}
  Rate:       #{loan.interest_rate}%
  Monthly:    #{loan.monthly_payment}
  """)
end)
```

## Fetching a Specific Loan

```elixir
{:ok, loan} = Tink.Loans.get_account(client, loan_id)

IO.inspect(loan.original_amount)    # Principal at origination
IO.inspect(loan.outstanding_amount) # Remaining balance
IO.inspect(loan.maturity_date)      # When the loan ends
```

## Loan Account Fields

| Field | Description |
|---|---|
| `id` | Tink account identifier |
| `name` | Loan display name |
| `type` | `"MORTGAGE"`, `"PERSONAL_LOAN"`, `"STUDENT_LOAN"`, `"AUTO"` |
| `balance` | Current outstanding balance as `Decimal` |
| `currency` | ISO 4217 currency code |
| `original_amount` | Original loan principal as `Decimal` |
| `interest_rate` | Annual interest rate as `Decimal` |
| `monthly_payment` | Scheduled monthly payment as `Decimal` |
| `maturity_date` | Loan end date |
| `provider_name` | Lender name |
| `start_date` | Loan origination date |

## Debt Summary

```elixir
{:ok, loans} = Tink.Loans.list_accounts(client)

total_debt = loans
  |> Enum.map(& &1.balance)
  |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

monthly_obligations = loans
  |> Enum.map(& &1.monthly_payment)
  |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

IO.puts("Total debt: #{total_debt}")
IO.puts("Monthly obligations: #{monthly_obligations}")
```
