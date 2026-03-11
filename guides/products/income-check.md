# Income Check

`Tink.IncomeCheck` analyses a user's transaction history to verify income
streams. Use it for affordability assessments, loan underwriting, or rent
qualification.

## Overview

Income Check connects to the user's bank account via Tink Link, fetches up to
12 months of transactions, and returns a structured report of detected income
sources with amounts, frequencies, and confidence scores.

## Starting a Session

```elixir
{:ok, session} = Tink.IncomeCheck.create_session(client,
  user_id:      "user_123",
  redirect_uri: "https://yourapp.com/callback",
  market:       "GB",
  months_back:  6
)

# Redirect the user to:
session.url
```

## Retrieving the Report

```elixir
{:ok, report} = Tink.IncomeCheck.get_report(client, session.id)

Enum.each(report.income_streams, fn stream ->
  IO.puts("""
  Source:    #{stream.name}
  Amount:    #{stream.amount} #{stream.currency}
  Frequency: #{stream.frequency}
  Status:    #{stream.status}
  """)
end)
```

## Generating a PDF

```elixir
{:ok, pdf_binary} = Tink.IncomeCheck.generate_pdf(client, session.id)
File.write!("income_report_#{session.id}.pdf", pdf_binary)
```

## Income Stream Fields

| Field | Description |
|---|---|
| `name` | Detected source name (e.g. employer name) |
| `amount` | Monthly net amount as `Decimal` |
| `currency` | ISO 4217 currency code |
| `frequency` | `"MONTHLY"`, `"WEEKLY"`, `"IRREGULAR"` |
| `status` | `"ACTIVE"` or `"INACTIVE"` |
| `type` | `"EMPLOYMENT"`, `"PENSION"`, `"BENEFIT"`, `"OTHER"` |
| `confidence` | Confidence score `0.0`–`1.0` |
| `transactions` | List of contributing transaction IDs |

## Report-Level Fields

| Field | Description |
|---|---|
| `total_monthly_income` | Sum of all active income streams |
| `currency` | Currency of the total |
| `period_from` | Start of the analysis window |
| `period_to` | End of the analysis window |
| `created_at` | Report generation timestamp |
