# Transactions

`Tink.Transactions` provides access to a user's full transaction history
across all connected bank accounts. Two sub-modules handle different consent
patterns: `Tink.TransactionsOneTimeAccess` and
`Tink.TransactionsContinuousAccess`.

## Listing Transactions

```elixir
{:ok, transactions} = Tink.Transactions.list(client,
  account_id: "acc_abc123",
  date_from:  "2024-01-01",
  date_to:    "2024-03-31"
)

Enum.each(transactions, fn tx ->
  IO.puts("#{tx.date}  #{tx.description}  #{tx.amount} #{tx.currency_code}")
end)
```

## Pagination

Transactions are paginated. Pass `next_page_token` to retrieve subsequent pages:

```elixir
defp fetch_all(client, opts, acc \\ []) do
  case Tink.Transactions.list(client, opts) do
    {:ok, %{transactions: txs, next_page_token: nil}} ->
      {:ok, acc ++ txs}

    {:ok, %{transactions: txs, next_page_token: token}} ->
      fetch_all(client, Keyword.put(opts, :page_token, token), acc ++ txs)

    {:error, _} = err ->
      err
  end
end
```

## One-Time Access

Use `Tink.TransactionsOneTimeAccess` when you need a single historical fetch
and do not require ongoing access:

```elixir
{:ok, session} = Tink.TransactionsOneTimeAccess.create_session(client,
  user_id:      "user_123",
  redirect_uri: "https://yourapp.com/callback",
  market:       "GB",
  months_back:  12
)
# Redirect user to session.url, then after callback:
{:ok, transactions} = Tink.TransactionsOneTimeAccess.get_transactions(client, session.id)
```

## Continuous Access

Use `Tink.TransactionsContinuousAccess` for ongoing transaction syncing
(e.g. personal finance apps):

```elixir
# Create a long-lived credential
{:ok, credential} = Tink.TransactionsContinuousAccess.create_credential(client,
  user_id:      "user_123",
  provider_name: "uk-ob-monzo",
  redirect_uri:  "https://yourapp.com/callback"
)

# Refresh transactions on demand
{:ok, _} = Tink.TransactionsContinuousAccess.refresh(client, credential.id)
{:ok, transactions} = Tink.Transactions.list(client, account_id: account_id)
```

## Transaction Fields

| Field | Description |
|---|---|
| `id` | Unique transaction ID |
| `account_id` | Account the transaction belongs to |
| `amount` | Transaction amount as `Decimal` |
| `currency_code` | ISO 4217 currency code |
| `date` | Transaction date (`Date`) |
| `description` | Raw description from the bank |
| `category_type` | Tink category (e.g. `"FOOD_AND_DRINK"`) |
| `status` | `"BOOKED"` or `"PENDING"` |
| `transaction_type` | `"DEBIT"` or `"CREDIT"` |
