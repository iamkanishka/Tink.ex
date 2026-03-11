defmodule Tink.IncomeCheck do
  @moduledoc """
  Income Check API for verifying user income and employment stability.

  This module provides comprehensive income verification capabilities to assess:
  - Monthly and annual income
  - Income stability and regularity
  - Employment status
  - Income sources and patterns

  ## Features

  - Retrieve detailed income reports
  - Generate PDF income verification documents
  - Analyze income stability
  - Identify primary income sources
  - Assess employment consistency

  ## Flow

      # Step 1: User completes Tink Link authentication
      # (Build Tink Link URL in Console > Income Check > Tink Link)
      # User authorizes and you receive income_check_id via redirect

      # Step 2: Get access token
      client = Tink.client(scope: "income-checks:readonly")

      # Step 3: Retrieve income report
      {:ok, report} = Tink.IncomeCheck.get_report(client, income_check_id)

      # Step 4: (Optional) Generate PDF report
      {:ok, pdf_binary} = Tink.IncomeCheck.get_report_pdf(client, income_check_id)

  ## Use Cases

  ### Loan Underwriting

      def verify_income_for_loan(client, income_check_id, required_monthly_income) do
        {:ok, report} = Tink.IncomeCheck.get_report(client, income_check_id)

        monthly_income = get_in(report, ["income", "monthlyIncome", "amount", "value"])
        stability_score = get_in(report, ["income", "stabilityScore"])

        cond do
          monthly_income < required_monthly_income ->
            {:reject, :insufficient_income}

          stability_score < 0.7 ->
            {:review, :unstable_income}

          true ->
            {:approve, :verified}
        end
      end

  ### Employment Verification

      def verify_employment_status(client, income_check_id) do
        {:ok, report} = Tink.IncomeCheck.get_report(client, income_check_id)

        employment = get_in(report, ["employment", "status"])
        income_regularity = get_in(report, ["income", "regularity"])

        %{
          employed: employment == "EMPLOYED",
          regular_income: income_regularity == "REGULAR",
          employer: get_in(report, ["employment", "employerName"]),
          start_date: get_in(report, ["employment", "startDate"])
        }
      end

  ### Rental Application

      def assess_rental_affordability(client, income_check_id, monthly_rent) do
        {:ok, report} = Tink.IncomeCheck.get_report(client, income_check_id)

        monthly_income = get_in(report, ["income", "monthlyIncome", "amount", "value"])

        # Standard 30% rule for rent
        max_affordable_rent = monthly_income * 0.30

        if monthly_rent <= max_affordable_rent do
          {:ok, :affordable}
        else
          {:error, :exceeds_30_percent_rule}
        end
      end

  ## Required Scope

  `income-checks:readonly`

  ## Links

  - [Income Check Documentation](https://docs.tink.com/resources/income-check/)
  - [Fetch Your First Report](https://docs.tink.com/resources/income-check/fetch-your-first-income-check-report)
  """

  alias Tink.{Cache, Client, Error}

  # Reports are immutable once generated — cache aggressively for 24 hours.
  @report_ttl :timer.hours(24)

  @doc """
  Retrieves an Income Check report as JSON.

  After the user completes authentication through Tink Link, you receive an
  `income_check_id`. Use this ID to retrieve a detailed income verification report.

  ## Parameters

    * `client` - Tink client with `income-checks:readonly` scope
    * `report_id` - Income check ID (received via redirect after user auth)

  ## Returns

    * `{:ok, report}` - Complete income verification report
    * `{:error, error}` - If the request fails

  ## Examples

      # After user completes Tink Link flow:
      # https://yourapp.com/callback?income_check_id=income_abc123

      client = Tink.client(scope: "income-checks:readonly")

      {:ok, report} = Tink.IncomeCheck.get_report(client, "income_abc123")
      #=> {:ok, %{
      #     "id" => "income_abc123",
      #     "userId" => "user_123",
      #     "status" => "COMPLETED",
      #     "createdAt" => "2024-01-15T10:00:00Z",
      #     "income" => %{
      #       "monthlyIncome" => %{
      #         "amount" => %{"value" => 45000.0, "currencyCode" => "SEK"},
      #         "confidence" => "HIGH"
      #       },
      #       "annualIncome" => %{
      #         "amount" => %{"value" => 540000.0, "currencyCode" => "SEK"},
      #         "confidence" => "HIGH"
      #       },
      #       "stabilityScore" => 0.92,
      #       "regularity" => "REGULAR",
      #       "sources" => [
      #         %{
      #           "type" => "SALARY",
      #           "employerName" => "Tech Corp AB",
      #           "monthlyAmount" => %{"value" => 45000.0, "currencyCode" => "SEK"},
      #           "frequency" => "MONTHLY",
      #           "firstObserved" => "2020-01-01",
      #           "lastObserved" => "2024-01-15"
      #         }
      #       ]
      #     },
      #     "employment" => %{
      #       "status" => "EMPLOYED",
      #       "employerName" => "Tech Corp AB",
      #       "startDate" => "2020-01-01",
      #       "employmentType" => "PERMANENT"
      #     },
      #     "analysisPeriod" => %{
      #       "start" => "2023-01-01",
      #       "end" => "2024-01-15",
      #       "months" => 12
      #     }
      #   }}

  ## Report Structure

  ### Income Information
  - **monthlyIncome**: Average monthly income with confidence level
  - **annualIncome**: Projected annual income
  - **stabilityScore**: Score from 0-1 indicating income consistency
  - **regularity**: REGULAR, IRREGULAR, or VARIABLE
  - **sources**: Detailed breakdown of income sources

  ### Employment Information
  - **status**: EMPLOYED, SELF_EMPLOYED, UNEMPLOYED
  - **employerName**: Name of employer (if employed)
  - **startDate**: Employment start date
  - **employmentType**: PERMANENT, TEMPORARY, CONTRACT

  ### Income Sources
  Each source includes:
  - Type (SALARY, BENEFITS, PENSION, etc.)
  - Employer/payer information
  - Amount and frequency
  - Date range of observations

  ## Use Cases

      # Check income stability
      {:ok, report} = Tink.IncomeCheck.get_report(client, income_check_id)

      stability = report["income"]["stabilityScore"]

      case stability do
        s when s >= 0.9 -> :very_stable
        s when s >= 0.7 -> :stable
        s when s >= 0.5 -> :moderately_stable
        _ -> :unstable
      end

      # Verify minimum income
      monthly = get_in(report, ["income", "monthlyIncome", "amount", "value"])

      if monthly >= 30000 do
        :approved
      else
        :denied
      end

      # Check employment duration
      start_date = Date.from_iso8601!(report["employment"]["startDate"])
      months_employed = Date.diff(Date.utc_today(), start_date) / 30

      if months_employed >= 6 do
        :meets_requirement
      else
        :insufficient_employment_history
      end

  ## Required Scope

  `income-checks:readonly`
  """
  @spec get_report(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_report(%Client{} = client, report_id) when is_binary(report_id) do
    url = "/v2/income-checks/#{report_id}"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key(["income-check", report_id])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @report_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end

  @doc """
  Generates a PDF version of the Income Check report.

  Returns a binary PDF document that can be saved or displayed.

  ## Parameters

    * `client` - Tink client with `income-checks:readonly` scope
    * `report_id` - Income check ID

  ## Returns

    * `{:ok, pdf_binary}` - PDF document as binary
    * `{:error, error}` - If the request fails

  ## Examples

      client = Tink.client(scope: "income-checks:readonly")

      {:ok, pdf_binary} = Tink.IncomeCheck.get_report_pdf(client, "income_abc123")

      # Save to file
      File.write!("income_report.pdf", pdf_binary)

      # Send as download in Phoenix
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s[attachment; filename="income_report.pdf"])
      |> send_resp(200, pdf_binary)

      # Upload to S3
      ExAws.S3.put_object("my-bucket", "reports/income_\#{report_id}.pdf", pdf_binary)
      |> ExAws.request()

  ## Use Cases

      # Generate PDF for loan application
      def generate_income_verification_pdf(client, income_check_id, applicant_id) do
        case Tink.IncomeCheck.get_report_pdf(client, income_check_id) do
          {:ok, pdf_binary} ->
            filename = "income_verification_\#{applicant_id}_\#{Date.utc_today()}.pdf"
            storage_path = Path.join(["documents", "income", filename])

            File.write!(storage_path, pdf_binary)

            {:ok, storage_path}

          {:error, error} ->
            {:error, error}
        end
      end

      # Email PDF to underwriter
      def email_income_report(client, income_check_id, underwriter_email) do
        {:ok, pdf} = Tink.IncomeCheck.get_report_pdf(client, income_check_id)

        Email.new()
        |> Email.to(underwriter_email)
        |> Email.subject("Income Verification Report")
        |> Email.attach(pdf, filename: "income_report.pdf")
        |> Mailer.deliver()
      end

  ## Required Scope

  `income-checks:readonly`
  """
  @spec get_report_pdf(Client.t(), String.t()) :: {:ok, binary()} | {:error, Error.t()}
  def get_report_pdf(%Client{} = client, report_id) when is_binary(report_id) do
    url = "/v2/income-checks/#{report_id}:generate-pdf"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key(["income-check-pdf", report_id])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @report_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end
end
