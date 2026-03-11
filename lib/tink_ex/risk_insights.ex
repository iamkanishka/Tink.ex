defmodule TinkEx.RiskInsights do
  @moduledoc """
  Risk Insights API for detailed financial risk analysis.

  This module provides deep insights into financial risk factors and behavioral
  patterns to support risk-based decision making:

  - Comprehensive risk analysis
  - Financial health indicators
  - Behavioral pattern detection
  - Predictive risk scoring
  - Detailed risk factor breakdown

  ## Features

  - **Multi-dimensional Risk Analysis**: Holistic view of financial health
  - **Predictive Indicators**: Early warning signals
  - **Behavioral Insights**: Spending and income patterns
  - **Risk Trends**: Historical risk trajectory
  - **Detailed Metrics**: Granular financial data points

  ## Flow

      # Step 1: User completes Tink Link authentication
      # (Build Tink Link URL in Console > Risk Insights > Tink Link)
      # User authorizes and you receive risk_insights_id via redirect

      # Step 2: Get access token
      client = TinkEx.client(scope: "risk-insights:readonly")

      # Step 3: Retrieve risk insights report
      {:ok, report} = TinkEx.RiskInsights.get_report(client, risk_insights_id)

  ## Use Cases

  ### Comprehensive Risk Assessment

      def perform_risk_assessment(client, risk_insights_id) do
        {:ok, report} = TinkEx.RiskInsights.get_report(client, risk_insights_id)

        assessment = %{
          overall_risk: report["overallRiskLevel"],
          financial_health_score: report["financialHealthScore"],
          stability_score: report["stabilityScore"],
          warning_signs: report["warningSignals"] || [],
          recommendation: determine_recommendation(report)
        }

        if assessment.overall_risk in ["HIGH", "CRITICAL"] do
          escalate_to_risk_team(assessment)
        end

        assessment
      end

  ### Early Warning Detection

      def detect_financial_stress(client, risk_insights_id) do
        {:ok, report} = TinkEx.RiskInsights.get_report(client, risk_insights_id)

        stress_indicators = [
          check_declining_balance(report),
          check_increasing_overdrafts(report),
          check_missed_payments(report),
          check_irregular_income(report),
          check_excessive_debt(report)
        ]
        |> Enum.filter(& &1)

        if length(stress_indicators) >= 3 do
          {:alert, :financial_stress_detected, stress_indicators}
        else
          {:ok, :normal}
        end
      end

  ### Portfolio Risk Management

      def assess_portfolio_risk(client, user_ids) do
        risk_distribution =
          Enum.map(user_ids, fn user_id ->
            risk_insights_id = get_latest_report_id(user_id)
            {:ok, report} = TinkEx.RiskInsights.get_report(client, risk_insights_id)

            %{
              user_id: user_id,
              risk_level: report["overallRiskLevel"],
              risk_score: report["riskScore"],
              exposure: calculate_exposure(user_id)
            }
          end)
          |> Enum.group_by(& &1.risk_level)

        %{
          high_risk_count: length(risk_distribution["HIGH"] || []),
          total_high_risk_exposure: calculate_total_exposure(risk_distribution["HIGH"]),
          portfolio_risk_score: calculate_portfolio_risk(risk_distribution)
        }
      end

  ### Credit Limit Adjustment

      def recommend_credit_limit_adjustment(client, risk_insights_id, current_limit) do
        {:ok, report} = TinkEx.RiskInsights.get_report(client, risk_insights_id)

        financial_health = report["financialHealthScore"]
        utilization = get_in(report, ["creditMetrics", "utilizationRate"])
        payment_behavior = get_in(report, ["paymentBehavior", "score"])

        cond do
          financial_health >= 80 && payment_behavior >= 90 ->
            {:increase, current_limit * 1.5}

          financial_health >= 60 && payment_behavior >= 70 ->
            {:maintain, current_limit}

          financial_health < 40 || payment_behavior < 50 ->
            {:decrease, current_limit * 0.5}

          true ->
            {:review, current_limit}
        end
      end

  ## Risk Levels

  - **LOW**: Minimal risk, strong financial health
  - **MODERATE**: Some risk factors, generally stable
  - **HIGH**: Significant risk, requires attention
  - **CRITICAL**: Severe risk, immediate action needed

  ## Warning Signals

  Common warning signals that may be detected:
  - `DECLINING_BALANCE` - Steady decrease in account balance
  - `INCREASING_OVERDRAFTS` - Growing overdraft frequency
  - `MISSED_PAYMENTS` - Payment defaults or delays
  - `IRREGULAR_INCOME` - Unstable income patterns
  - `HIGH_DEBT_RATIO` - Debt exceeds healthy levels
  - `GAMBLING_ACTIVITY` - Gambling transactions detected
  - `PAYDAY_LOAN_USAGE` - High-cost lending usage
  - `ACCOUNT_CHURN` - Frequent account changes

  ## Required Scope

  `risk-insights:readonly`

  ## Links

  - [Risk Insights Documentation](https://docs.tink.com/resources/risk-insights/)
  - [Fetch Your First Report](https://docs.tink.com/resources/risk-insights/fetch-your-first-risk-insights-report)
  """

  alias TinkEx.{Client, Error}

  @doc """
  Retrieves a Risk Insights report.

  After the user completes authentication through Tink Link, you receive a
  `risk_insights_id`. Use this ID to retrieve a detailed risk insights report.

  ## Parameters

    * `client` - TinkEx client with `risk-insights:readonly` scope
    * `report_id` - Risk insights ID (received via redirect after user auth)

  ## Returns

    * `{:ok, report}` - Complete risk insights report
    * `{:error, error}` - If the request fails

  ## Examples

      # After user completes Tink Link flow:
      # https://yourapp.com/callback?risk_insights_id=risk_ins_abc123

      client = TinkEx.client(scope: "risk-insights:readonly")

      {:ok, report} = TinkEx.RiskInsights.get_report(client, "risk_ins_abc123")
      #=> {:ok, %{
      #     "id" => "risk_ins_abc123",
      #     "userId" => "user_123",
      #     "status" => "COMPLETED",
      #     "createdAt" => "2024-01-15T10:00:00Z",
      #     "overallRiskLevel" => "MODERATE",
      #     "riskScore" => 42.5,
      #     "financialHealthScore" => 68.0,
      #     "stabilityScore" => 75.5,
      #     "warningSignals" => [
      #       "DECLINING_BALANCE",
      #       "HIGH_DEBT_RATIO"
      #     ],
      #     "analysisPeriod" => %{
      #       "start" => "2023-01-01",
      #       "end" => "2024-01-15",
      #       "months" => 12
      #     },
      #     "incomeAnalysis" => %{
      #       "averageMonthlyIncome" => %{
      #         "amount" => %{"value" => 42000.0, "currencyCode" => "SEK"}
      #       },
      #       "stabilityScore" => 0.85,
      #       "trend" => "STABLE",
      #       "sources" => [
      #         %{
      #           "type" => "SALARY",
      #           "percentage" => 95.0,
      #           "regularity" => "MONTHLY"
      #         },
      #         %{
      #           "type" => "OTHER",
      #           "percentage" => 5.0,
      #           "regularity" => "IRREGULAR"
      #         }
      #       ]
      #     },
      #     "spendingAnalysis" => %{
      #       "averageMonthlySpending" => %{
      #         "amount" => %{"value" => 38000.0, "currencyCode" => "SEK"}
      #       },
      #       "trend" => "INCREASING",
      #       "volatility" => "MODERATE",
      #       "categoryBreakdown" => %{
      #         "housing" => 35.0,
      #         "groceries" => 15.0,
      #         "transportation" => 12.0,
      #         "entertainment" => 8.0,
      #         "other" => 30.0
      #       }
      #     },
      #     "balanceMetrics" => %{
      #       "averageBalance" => %{
      #         "amount" => %{"value" => 8500.0, "currencyCode" => "SEK"}
      #       },
      #       "minimumBalance" => %{
      #         "amount" => %{"value" => 1200.0, "currencyCode" => "SEK"}
      #       },
      #       "trend" => "DECLINING",
      #       "volatility" => "HIGH",
      #       "daysInOverdraft" => 12
      #     },
      #     "creditMetrics" => %{
      #       "totalCreditLimit" => %{
      #         "amount" => %{"value" => 50000.0, "currencyCode" => "SEK"}
      #       },
      #       "totalCreditUsed" => %{
      #         "amount" => %{"value" => 32000.0, "currencyCode" => "SEK"}
      #       },
      #       "utilizationRate" => 0.64,
      #       "overdraftCount" => 5,
      #       "averageOverdraftAmount" => %{
      #         "amount" => %{"value" => 3500.0, "currencyCode" => "SEK"}
      #       }
      #     },
      #     "paymentBehavior" => %{
      #       "score" => 72.0,
      #       "onTimePayments" => 85.0,
      #       "latePayments" => 15.0,
      #       "missedPayments" => 0.0,
      #       "averageDaysLate" => 3.5
      #     },
      #     "debtMetrics" => %{
      #       "totalDebt" => %{
      #         "amount" => %{"value" => 250000.0, "currencyCode" => "SEK"}
      #       },
      #       "debtToIncomeRatio" => 0.49,
      #       "monthlyDebtPayments" => %{
      #         "amount" => %{"value" => 8500.0, "currencyCode" => "SEK"}
      #       },
      #       "debtServiceRatio" => 0.20
      #     },
      #     "savingsBehavior" => %{
      #       "monthlySavingsRate" => 0.10,
      #       "trend" => "DECLINING",
      #       "averageMonthlySavings" => %{
      #         "amount" => %{"value" => 4000.0, "currencyCode" => "SEK"}
      #       }
      #     },
      #     "riskFactors" => [
      #       %{
      #         "factor" => "DECLINING_BALANCE",
      #         "severity" => "MEDIUM",
      #         "impact" => "Account balance has decreased by 35% over 6 months",
      #         "recommendation" => "Monitor spending and increase savings"
      #       },
      #       %{
      #         "factor" => "HIGH_DEBT_RATIO",
      #         "severity" => "MEDIUM",
      #         "impact" => "Debt-to-income ratio at 49% is approaching concerning levels",
      #         "recommendation" => "Consider debt consolidation or reduction strategy"
      #       }
      #     ],
      #     "trends" => %{
      #       "income" => "STABLE",
      #       "spending" => "INCREASING",
      #       "balance" => "DECLINING",
      #       "debt" => "STABLE"
      #     },
      #     "predictions" => %{
      #       "nextMonthBalance" => %{
      #         "amount" => %{"value" => 6500.0, "currencyCode" => "SEK"},
      #         "confidence" => "MEDIUM"
      #       },
      #       "riskTrajectory" => "INCREASING",
      #       "financialStressLikelihood" => 0.35
      #     },
      #     "recommendations" => [
      #       "Reduce discretionary spending by 15%",
      #       "Build emergency fund to 3 months expenses",
      #       "Review and optimize debt payments"
      #     ],
      #     "confidence" => "HIGH"
      #   }}

  ## Report Structure

  ### Overall Assessment
  - **overallRiskLevel**: LOW, MODERATE, HIGH, CRITICAL
  - **riskScore**: Numerical risk score (0-100)
  - **financialHealthScore**: Overall health score (0-100)
  - **stabilityScore**: Financial stability score (0-100)
  - **warningSignals**: List of detected warning signals

  ### Income Analysis
  - Average monthly income
  - Income stability and trend
  - Income sources breakdown
  - Regularity assessment

  ### Spending Analysis
  - Average monthly spending
  - Spending trends and volatility
  - Category breakdown
  - Discretionary vs essential spending

  ### Balance Metrics
  - Average and minimum balance
  - Balance trends
  - Overdraft frequency and duration
  - Balance volatility

  ### Credit Metrics
  - Credit limits and utilization
  - Overdraft statistics
  - Credit behavior patterns

  ### Payment Behavior
  - Payment history score
  - On-time payment percentage
  - Late and missed payments
  - Average delay duration

  ### Debt Metrics
  - Total debt amount
  - Debt-to-income ratio
  - Monthly debt payments
  - Debt service ratio

  ### Savings Behavior
  - Monthly savings rate
  - Savings trends
  - Average monthly savings

  ### Risk Factors
  Detailed breakdown of each risk factor:
  - Factor type and severity
  - Impact description
  - Recommendations

  ### Trends
  - Income trend
  - Spending trend
  - Balance trend
  - Debt trend

  ### Predictions
  - Next month balance prediction
  - Risk trajectory
  - Financial stress likelihood

  ## Use Cases

      # Monitor financial health deterioration
      {:ok, report} = TinkEx.RiskInsights.get_report(client, report_id)

      if report["predictions"]["riskTrajectory"] == "INCREASING" do
        trigger_proactive_outreach()
      end

      # Credit limit decision
      financial_health = report["financialHealthScore"]
      debt_ratio = get_in(report, ["debtMetrics", "debtToIncomeRatio"])

      approved = financial_health >= 70 && debt_ratio < 0.40

      # Early intervention
      if "DECLINING_BALANCE" in (report["warningSignals"] || []) do
        offer_financial_counseling()
      end

      # Risk-based pricing
      risk_premium = case report["overallRiskLevel"] do
        "LOW" -> 0.0
        "MODERATE" -> 1.5
        "HIGH" -> 3.5
        "CRITICAL" -> nil  # Reject
      end

  ## Required Scope

  `risk-insights:readonly`
  """
  @spec get_report(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_report(%Client{} = client, report_id) when is_binary(report_id) do
    url = "/risk/v1/risk-insights/#{report_id}"

    Client.get(client, url)
  end
end
