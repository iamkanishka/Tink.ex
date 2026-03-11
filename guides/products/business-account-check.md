# Business Account Check

`Tink.BusinessAccountCheck` verifies bank account ownership for business
entities. It extends Account Check with company-specific fields such as
registered company name and company number.

## Overview

Business Account Check is designed for B2B payment flows where you need to
confirm that the payer or payee is the legitimate owner of a business bank
account before initiating a transfer.

## Starting a Session

```elixir
{:ok, session} = Tink.BusinessAccountCheck.create_session(client,
  user_id:      "business_user_456",
  redirect_uri: "https://yourapp.com/business/callback",
  market:       "GB"
)

# Redirect the business user to:
session.url
```

## Retrieving the Report

```elixir
{:ok, report} = Tink.BusinessAccountCheck.get_report(client, session.id)

IO.inspect(report.company_name)    # "Acme Ltd"
IO.inspect(report.company_number)  # "12345678"
IO.inspect(report.iban)            # "GB29NWBK60161331926819"
IO.inspect(report.verification_status)  # "VERIFIED"
```

## Verification Status Values

| Status | Meaning |
|---|---|
| `VERIFIED` | Account ownership confirmed for the given company |
| `PARTIAL` | Some fields verified but not all |
| `FAILED` | Verification could not be completed |

## Report Fields

| Field | Description |
|---|---|
| `company_name` | Registered company name |
| `company_number` | Companies House / local registry number |
| `iban` | IBAN of the verified account |
| `account_holder_name` | Name on the bank account |
| `verification_status` | Outcome of the verification |
| `provider_name` | Bank that was used for verification |
| `created_at` | Timestamp of the verification |

## Credential Management

Business users may have multiple sets of credentials:

```elixir
{:ok, credentials} = Tink.BusinessAccountCheck.list_credentials(client, user_id)
{:ok, _}           = Tink.BusinessAccountCheck.delete_credential(client, user_id, cred_id)
```
