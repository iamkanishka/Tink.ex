defmodule Tink.BusinessAccountCheck do
  @moduledoc """
  Business Account Check API for verifying business account ownership.

  This module provides business account verification capabilities, similar to
  Account Check but specifically designed for business accounts.

  ## Features

  - Verify business account ownership
  - Retrieve business account verification reports
  - Support for business-specific verification requirements

  ## Flow

      # Step 1: Build Tink Link URL in Console
      # Go to Console > Business Account Check > Tink Link
      # User completes authentication flow
      # Receive business_account_verification_report_id via redirect

      # Step 2: Get access token
      client = Tink.client(scope: "business-account-verification-reports:read")

      # Step 3: Retrieve report
      {:ok, report} = Tink.BusinessAccountCheck.get_report(client, report_id)

  ## Use Cases

  ### Business KYC Verification

      @spec verify_business_account(String.t()) :: {:ok, map()} | {:error, Error.t()}

      def verify_business_account(business_id) do
        # Generate Tink Link for business
        tink_link = generate_business_tink_link(business_id)

        # After business completes authentication
        {:ok, report} = Tink.BusinessAccountCheck.get_report(
          client,
          report_id_from_redirect
        )

        verify_business_details(report)
      end

  ### B2B Partner Verification

      @spec verify_partner_account(String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}

      def verify_partner_account(partner_id, report_id) do
        {:ok, report} = Tink.BusinessAccountCheck.get_report(client, report_id)

        %{
          verified: report["verified"],
          business_name: report["businessName"],
          account_details: report["accountDetails"],
          verification_date: report["verificationTimestamp"]
        }
      end

  ## Required Scope

  `business-account-verification-reports:read`

  ## Links

  - [Business Account Check Documentation](https://docs.tink.com/resources/business-account-check/)
  - [Fetch Your First Report](https://docs.tink.com/resources/business-account-check/fetch-your-first-business-account-check-report)
  """

  alias Tink.{Cache, Client, Error}

  # Reports are immutable once generated — cache for 24 hours.
  @report_ttl :timer.hours(24)

  @doc """
  Retrieves a business account verification report.

  After a business user completes the authentication flow through Tink Link,
  you receive a `business_account_verification_report_id`. Use this ID to
  retrieve the complete verification report.

  ## Parameters

    * `client` - Tink client with `business-account-verification-reports:read` scope
    * `report_id` - Business account verification report ID from redirect

  ## Returns

    * `{:ok, report}` - Complete business account verification report
    * `{:error, error}` - If the request fails

  ## Examples

      # After business user completes flow, you receive report_id:
      # https://yourapp.com/callback?business_account_verification_report_id=report_abc123

      client = Tink.client(scope: "business-account-verification-reports:read")

      {:ok, report} = Tink.BusinessAccountCheck.get_report(client, "report_abc123")
      #=> {:ok, %{
      #     "id" => "report_abc123",
      #     "verified" => true,
      #     "businessName" => "Acme Corporation AB",
      #     "organizationNumber" => "556677-8899",
      #     "accountDetails" => %{
      #       "iban" => "SE1234567890123456789012",
      #       "accountNumber" => "1234567890",
      #       "clearingNumber" => "8765",
      #       "accountHolderName" => "Acme Corporation AB"
      #     },
      #     "verification" => %{
      #       "status" => "VERIFIED",
      #       "timestamp" => "2024-01-15T10:30:00Z"
      #     },
      #     "businessInformation" => %{
      #       "companyType" => "AB",
      #       "registrationDate" => "2020-01-01",
      #       "registeredAddress" => %{
      #         "street" => "Kungsgatan 1",
      #         "city" => "Stockholm",
      #         "postalCode" => "111 22",
      #         "country" => "SE"
      #       }
      #     }
      #   }}

      # Verify business identity
      if report["verified"] do
        proceed_with_onboarding(report)
      else
        request_manual_verification(report)
      end

  ## Report Structure

  The report includes:
  - Business verification status
  - Company details (name, org number, type)
  - Account information (IBAN, account number)
  - Business address and registration info
  - Verification timestamp

  ## Required Scope

  `business-account-verification-reports:read`
  """
  @spec get_report(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_report(%Client{} = client, report_id) when is_binary(report_id) do
    url = "/data/v1/business-account-verification-reports/#{report_id}"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key(["business-account-check", report_id])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @report_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end
end
