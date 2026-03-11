defmodule Tink.RiskCategorisation do
  @moduledoc """
  Risk Categorisation API for assessing financial risk profiles.

  This module provides comprehensive risk assessment capabilities to categorize
  users based on their financial behavior and transaction patterns:

  - Spending behavior analysis
  - Financial risk scoring
  - Transaction pattern categorization
  - Risk indicators and flags
  - Behavioral risk assessment

  ## Features

  - **Risk Categories**: Low, Medium, High, Very High risk classification
  - **Behavioral Analysis**: Spending patterns and financial habits
  - **Risk Indicators**: Specific risk flags (gambling, excessive spending, etc.)
  - **Trend Analysis**: Changes in financial behavior over time
  - **Comprehensive Scoring**: Multi-factor risk assessment

  ## Flow

      # Step 1: User completes Tink Link authentication
      # (Build Tink Link URL in Console > Risk Categorisation > Tink Link)
      # User authorizes and you receive risk_categorisation_id via redirect

      # Step 2: Get access token
      client = Tink.client(scope: "risk-categorisation:readonly")

      # Step 3: Retrieve risk categorisation report
      {:ok, report} = Tink.RiskCategorisation.get_report(client, risk_categorisation_id)

  ## Use Cases

  ### Loan Risk Assessment

      def assess_loan_risk(client, risk_categorisation_id, loan_amount) do
        {:ok, report} = Tink.RiskCategorisation.get_report(client, risk_categorisation_id)

        risk_category = report["riskCategory"]
        risk_score = report["riskScore"]

        case risk_category do
          "LOW" ->
            {:approve, :low_risk}

          "MEDIUM" ->
            if loan_amount < 50000, do: {:approve, :medium_risk}, else: {:review, :medium_risk}

          "HIGH" ->
            {:review, :high_risk}

          "VERY_HIGH" ->
            {:reject, :very_high_risk}
        end
      end

  ### Credit Card Approval

      def evaluate_credit_card_application(client, risk_categorisation_id) do
        {:ok, report} = Tink.RiskCategorisation.get_report(client, risk_categorisation_id)

        risk_flags = report["riskIndicators"] || []

        cond do
          "GAMBLING" in risk_flags ->
            {:reject, :gambling_detected}

          "EXCESSIVE_SPENDING" in risk_flags ->
            {:reject, :poor_financial_management}

          report["riskCategory"] in ["LOW", "MEDIUM"] ->
            {:approve, determine_credit_limit(report)}

          true ->
            {:reject, :high_risk}
        end
      end

  ### Account Monitoring

      def monitor_account_risk(client, risk_categorisation_id) do
        {:ok, report} = Tink.RiskCategorisation.get_report(client, risk_categorisation_id)

        previous_category = get_previous_risk_category(risk_categorisation_id)

        if risk_increased?(previous_category, report["riskCategory"]) do
          notify_risk_team(%{
            user_id: report["userId"],
            old_risk: previous_category,
            new_risk: report["riskCategory"],
            indicators: report["riskIndicators"]
          })
        end

        :ok
      end

  ## Risk Categories

  - **LOW**: Minimal risk, stable financial behavior
  - **MEDIUM**: Moderate risk, some concerning patterns
  - **HIGH**: Significant risk, multiple warning signs
  - **VERY_HIGH**: Severe risk, immediate attention required

  ## Risk Indicators

  Common risk flags that may be present:
  - `GAMBLING` - Gambling-related transactions
  - `EXCESSIVE_SPENDING` - Spending beyond means
  - `OVERDRAFTS` - Frequent overdraft usage
  - `PAYDAY_LOANS` - Use of payday lending services
  - `DEBT_COLLECTION` - Debt collection activity
  - `RETURNED_PAYMENTS` - Failed payment attempts
  - `IRREGULAR_INCOME` - Inconsistent income patterns
  - `HIGH_CREDIT_UTILIZATION` - Maxing out credit limits

  ## Required Scope

  `risk-categorisation:readonly`

  ## Links

  - [Risk Categorisation Documentation](https://docs.tink.com/resources/risk-categorisation/)
  - [Fetch Your First Report](https://docs.tink.com/resources/risk-categorisation/fetch-your-first-risk-categorisation-report)
  """

  alias Tink.{Cache, Client, Error}

  # Reports are immutable once generated — cache for 24 hours.
  @report_ttl :timer.hours(24)

  @doc """
  Retrieves a Risk Categorisation report.

  After the user completes authentication through Tink Link, you receive a
  `risk_categorisation_id`. Use this ID to retrieve a comprehensive risk
  assessment report.

  ## Parameters

    * `client` - Tink client with `risk-categorisation:readonly` scope
    * `report_id` - Risk categorisation ID (received via redirect after user auth)

  ## Returns

    * `{:ok, report}` - Complete risk categorisation report
    * `{:error, error}` - If the request fails

  ## Examples

      # After user completes Tink Link flow:
      # https://yourapp.com/callback?risk_categorisation_id=risk_cat_abc123

      client = Tink.client(scope: "risk-categorisation:readonly")

      {:ok, report} = Tink.RiskCategorisation.get_report(client, "risk_cat_abc123")
      #=> {:ok, %{
      #     "id" => "risk_cat_abc123",
      #     "userId" => "user_123",
      #     "status" => "COMPLETED",
      #     "createdAt" => "2024-01-15T10:00:00Z",
      #     "riskCategory" => "MEDIUM",
      #     "riskScore" => 45.5,
      #     "riskIndicators" => [
      #       "OVERDRAFTS",
      #       "HIGH_CREDIT_UTILIZATION"
      #     ],
      #     "analysisPeriod" => %{
      #       "start" => "2023-01-01",
      #       "end" => "2024-01-15",
      #       "months" => 12
      #     },
      #     "spendingBehavior" => %{
      #       "averageMonthlySpending" => %{
      #         "amount" => %{"value" => 28000.0, "currencyCode" => "SEK"}
      #       },
      #       "spendingVariability" => "MODERATE",
      #       "essentialSpendingRatio" => 0.65,
      #       "discretionarySpendingRatio" => 0.35
      #     },
      #     "incomeStability" => %{
      #       "stabilityScore" => 0.82,
      #       "regularity" => "REGULAR",
      #       "averageMonthlyIncome" => %{
      #         "amount" => %{"value" => 35000.0, "currencyCode" => "SEK"}
      #       }
      #     },
      #     "creditBehavior" => %{
      #       "overdraftFrequency" => 3,
      #       "averageOverdraftAmount" => %{
      #         "amount" => %{"value" => 2500.0, "currencyCode" => "SEK"}
      #       },
      #       "creditUtilizationRatio" => 0.72,
      #       "paymentHistory" => "MOSTLY_ON_TIME"
      #     },
      #     "riskFactors" => [
      #       %{
      #         "type" => "OVERDRAFTS",
      #         "severity" => "MEDIUM",
      #         "frequency" => 3,
      #         "impact" => "Frequent overdraft usage indicates cash flow issues"
      #       },
      #       %{
      #         "type" => "HIGH_CREDIT_UTILIZATION",
      #         "severity" => "MEDIUM",
      #         "value" => 0.72,
      #         "impact" => "High credit utilization may indicate financial stress"
      #       }
      #     ],
      #     "categoryBreakdown" => %{
      #       "gambling" => %{
      #         "monthlyAverage" => %{"value" => 0.0, "currencyCode" => "SEK"},
      #         "percentageOfSpending" => 0.0
      #       },
      #       "paydayLoans" => %{
      #         "detected" => false,
      #         "count" => 0
      #       },
      #       "debtCollection" => %{
      #         "detected" => false,
      #         "count" => 0
      #       }
      #     },
      #     "recommendation" => "MODERATE_RISK",
      #     "confidence" => "HIGH"
      #   }}

  ## Report Structure

  ### Risk Assessment
  - **riskCategory**: Overall risk classification (LOW/MEDIUM/HIGH/VERY_HIGH)
  - **riskScore**: Numerical score (0-100, higher = more risk)
  - **riskIndicators**: List of detected risk flags
  - **confidence**: Assessment confidence level

  ### Spending Behavior
  - **averageMonthlySpending**: Average spending amount
  - **spendingVariability**: LOW, MODERATE, HIGH
  - **essentialSpendingRatio**: Percentage on necessities
  - **discretionarySpendingRatio**: Percentage on non-essentials

  ### Income Stability
  - **stabilityScore**: Income consistency (0-1)
  - **regularity**: REGULAR, IRREGULAR, VARIABLE
  - **averageMonthlyIncome**: Average income amount

  ### Credit Behavior
  - **overdraftFrequency**: Number of overdrafts in period
  - **creditUtilizationRatio**: Percentage of credit limit used
  - **paymentHistory**: ON_TIME, MOSTLY_ON_TIME, LATE, VERY_LATE

  ### Risk Factors
  Detailed breakdown of each risk factor:
  - Type and severity
  - Frequency or value
  - Impact description

  ### Category Breakdown
  - Gambling activity
  - Payday loan usage
  - Debt collection presence
  - Other high-risk categories

  ## Use Cases

      # Check for specific risk indicators
      {:ok, report} = Tink.RiskCategorisation.get_report(client, report_id)

      if "GAMBLING" in (report["riskIndicators"] || []) do
        flag_for_manual_review()
      end

      # Calculate risk-based pricing
      risk_score = report["riskScore"]

      interest_rate = case risk_score do
        score when score < 25 -> 3.5  # Low risk
        score when score < 50 -> 5.5  # Medium risk
        score when score < 75 -> 8.5  # High risk
        _ -> nil  # Reject
      end

      # Monitor credit utilization
      utilization = get_in(report, ["creditBehavior", "creditUtilizationRatio"])

      if utilization > 0.8 do
        send_credit_limit_warning()
      end

      # Check income stability
      stability = get_in(report, ["incomeStability", "stabilityScore"])

      if stability < 0.6 do
        require_additional_verification()
      end

  ## Required Scope

  `risk-categorisation:readonly`
  """
  @spec get_report(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_report(%Client{} = client, report_id) when is_binary(report_id) do
    url = "/risk/v2/risk-categorisation/reports/#{report_id}"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key(["risk-categorisation", report_id])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @report_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end
end
