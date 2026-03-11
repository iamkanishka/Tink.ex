# Account Check

`Tink.AccountCheck` enables instant verification of bank account ownership.
Use it to confirm that a user owns the account before initiating payments or
payouts.

## Overview

Account Check works by directing the user through a Tink Link flow where they
authenticate with their bank. Tink then returns a signed report confirming
account ownership, holder name, and account number.

## Starting a Session

```elixir
{:ok, session} = Tink.AccountCheck.create_session(client,
  user_id:      "user_123",
  redirect_uri: "https://yourapp.com/callback",
  market:       "GB"
)

# Redirect the user to:
session.url
```

## Retrieving the Report

After the user completes the flow and your callback receives the `code`:

```elixir
{:ok, report} = Tink.AccountCheck.get_report(client, session.id)

IO.inspect(report.account_holder_name)   # "Jane Smith"
IO.inspect(report.iban)                  # "GB29NWBK60161331926819"
IO.inspect(report.verification_status)  # "VERIFIED"
```

## Consent Management

Update or revoke consent after initial authorisation:

```elixir
# Extend consent
{:ok, _} = Tink.AccountCheck.update_consent(client, session.id,
  expires_at: DateTime.add(DateTime.utc_now(), 90, :day)
)

# Revoke
{:ok, _} = Tink.AccountCheck.revoke_consent(client, session.id)
```

## User & Credential Management

AccountCheck delegates user/credential operations to `Tink.Users`:

```elixir
{:ok, user}  = Tink.AccountCheck.create_user(client, market: "GB", locale: "en_GB")
{:ok, creds} = Tink.AccountCheck.list_credentials(client, user.id)
```

## Report Fields

| Field | Description |
|---|---|
| `account_holder_name` | Legal name of the account holder |
| `iban` | IBAN of the verified account |
| `bban` | BBAN / sort code + account number |
| `verification_status` | `VERIFIED`, `PARTIAL`, or `FAILED` |
| `created_at` | Timestamp of the verification |
| `provider_name` | Name of the bank that was connected |
