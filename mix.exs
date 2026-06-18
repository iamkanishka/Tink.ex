defmodule Tink.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/iamkanishka/tink.ex"

  def project do
    [
      app: :tink,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix],
        flags: [:error_handling, :underspecs]
      ],
      name: "Tink",
      source_url: @source_url
    ]
  end

  # `test/support` contains shared test helpers/fixtures (`Tink.TestHelpers`)
  # used across the suite. Without this, `mix test` fails to compile with
  # "module Tink.TestHelpers is not loaded and could not be found".
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key],
      mod: {Tink.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP
      {:finch, "~> 0.16"},
      {:jason, "~> 1.4"},

      # Caching — guide specifies 4.1
      {:cachex, "~> 4.1"},

      # Rate limiting
      {:hammer, "~> 6.2"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Optional — only needed if you use Tink.WebhookVerifier.verify_plug/2.
      # Core webhook verification (verify/2, verify_with_config/2) has no
      # dependency on Plug.
      {:plug, "~> 1.14", optional: true},

      # Dev/Test
      {:bypass, "~> 2.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "A complete, production-grade Elixir client for the Tink Open Banking API. " <>
      "Covers all Tink products: data aggregation, enrichment, payments, VRP, " <>
      "risk insights, income/expense checks, savings goals, PFM, and more."
  end

  defp package do
    [
      name: "tink",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Tink Docs" => "https://docs.tink.com"
      },
      maintainers: ["Kanishka Naik"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/advanced/authentication.md",
        "guides/advanced/caching.md",
        "guides/advanced/error-handling.md",
        "guides/advanced/rate-limiting.md",
        "LICENSE"
      ],
      groups_for_modules: [
        Core: [Tink, Tink.Client, Tink.Config, Tink.Error],
        Auth: [Tink.Auth, Tink.AuthToken],
        "Data Aggregation": [
          Tink.Users,
          Tink.Accounts,
          Tink.Transactions,
          Tink.Credentials,
          Tink.Providers,
          Tink.Identities,
          Tink.Investments,
          Tink.Loans,
          Tink.Statistics,
          Tink.FinancialCalendar
        ],
        Enrichment: [
          Tink.Enrichment,
          Tink.Enrichment.Transactions,
          Tink.Enrichment.Recurring,
          Tink.Enrichment.Categories,
          Tink.Enrichment.Merchants,
          Tink.Enrichment.Sustainability,
          Tink.Enrichment.OnDemand
        ],
        "Verification & Risk": [
          Tink.AccountCheck,
          Tink.BusinessAccountCheck,
          Tink.IncomeCheck,
          Tink.ExpenseCheck,
          Tink.RiskInsights,
          Tink.BalanceCheck
        ],
        Payments: [
          Tink.Payments,
          Tink.MandatePayments,
          Tink.Mandates,
          Tink.BulkPayments,
          Tink.SettlementAccounts
        ],
        "Finance Management": [
          Tink.Budgets,
          Tink.SavingsGoals,
          Tink.Subscriptions,
          Tink.CostOfLiving,
          Tink.Insights,
          Tink.CashFlow
        ],
        "Connectivity & Consents": [
          Tink.Connectivity,
          Tink.Consents,
          Tink.ProviderConsents,
          Tink.BalanceCheck
        ],
        Infrastructure: [
          Tink.Connector,
          Tink.Webhooks,
          Tink.WebhookHandler,
          Tink.WebhookVerifier,
          Tink.Link,
          Tink.ReportJobs,
          Tink.Merchants,
          Tink.TransactionReports
        ],
        Internal: [
          Tink.HTTP,
          Tink.HTTP.Finch,
          Tink.HTTP.MutualTLS,
          Tink.HTTP.Behaviour,
          Tink.Cache,
          Tink.RateLimiter,
          Tink.Paginator,
          Tink.Telemetry,
          Tink.Application
        ]
      ]
    ]
  end

  defp aliases do
    [
      "test.ci": ["test --cover --warnings-as-errors"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
