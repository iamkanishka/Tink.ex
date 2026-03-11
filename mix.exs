defmodule Tink.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/iamkanishka/tink.ex"

  def project do
    [
      app: :tink,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Tink",
      source_url: @source_url,
      homepage_url: @source_url,

      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Dialyzer configuration
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:ex_unit, :mix],
        ignore_warnings: ".dialyzer_ignore.exs",
        flags: [:error_handling, :underspecs]
      ],

      # Aliases
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl, :public_key],
      mod: {Tink.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP client
      {:finch, "~> 0.21"},
      {:jason, "~> 1.4"},
      {:mint, "~> 1.7"},

      # OAuth & JWT
      {:oauth2, "~> 2.1", optional: true},
      {:joken, "~> 2.6", optional: true},

      # Financial calculations
      {:decimal, "~> 2.3"},

      # Utilities
      {:telemetry, "~> 1.3"},
      {:nimble_options, "~> 1.1"},

      # Caching & Rate Limiting (Optional)
      {:cachex, "~> 4.1", optional: true},
      {:hammer, "~> 7.2", optional: true},

      # Development & Documentation
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},

      # Testing
      {:mox, "~> 1.2", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp description do
    """
    Production-ready Elixir client for the Tink open banking API. Provides
    comprehensive access to account aggregation, transaction data, financial
    insights, account verification, income verification, and payment initiation
    services.
    """
  end

  defp package do
    [
      name: "tink",
      files: ~w(
        lib
        .formatter.exs
        mix.exs
        README.md
        LICENSE.txt
        CHANGELOG.md
      ),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/tink"
      },
      maintainers: ["Kanishka"]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Tink",
      source_ref: "v#{@version}",
      canonical: "https://hexdocs.pm/tink",
      source_url: @source_url,
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      groups_for_functions: [
        "API Resources": &(&1[:section] == :api),
        Configuration: &(&1[:section] == :config),
        Utilities: &(&1[:section] == :util)
      ]
    ]
  end

  defp extras do
    [
      # Main documentation
      "README.md",
      "CHANGELOG.md",
      "LICENSE.txt",

      # Guides
      "guides/getting-started.md",
      "guides/authentication.md",
      "guides/configuration.md",

      # Product guides
      "guides/account-check.md",
      "guides/balance-check.md",
      "guides/business-account-check.md",
      "guides/transactions.md",
      "guides/income-check.md",
      "guides/expense-check.md",
      "guides/risk-insights.md",
      "guides/investments.md",
      "guides/loans.md",
      "guides/budgets.md",

      # Advanced guides
      "guides/error-handling.md",
      "guides/testing.md",
      "guides/rate-limiting.md",
      "guides/caching.md",
      "guides/telemetry.md",
      "guides/webhooks.md"
    ]
  end

  defp groups_for_extras do
    [
      "Getting Started": ~r/guides\/(getting-started|authentication|configuration)/,
      Products: ~r/guides\/products/,
      Advanced: ~r/guides\/advanced/
    ]
  end

  defp groups_for_modules do
    [
      Core: [
        Tink,
        Tink.Client,
        Tink.Config,
        Tink.Auth,
        Tink.AuthToken,
        Tink.Error
      ],
      "Account Aggregation": [
        Tink.Transactions,
        Tink.TransactionsOneTimeAccess,
        Tink.TransactionsContinuousAccess,
        Tink.Accounts,
        Tink.Users,
        Tink.Categories,
        Tink.Statistics
      ],
      "Verification & Insights": [
        Tink.AccountCheck,
        Tink.IncomeCheck,
        Tink.ExpenseCheck,
        Tink.RiskCategorisation,
        Tink.RiskInsights,
        Tink.BusinessAccountCheck,
        Tink.BalanceCheck
      ],
      "Finance Management": [
        Tink.Budgets,
        Tink.CashFlow,
        Tink.FinancialCalendar
      ],
      "Investment & Loans": [
        Tink.Investments,
        Tink.Loans
      ],
      Infrastructure: [
        Tink.Providers,
        Tink.Connectivity,
        Tink.Link,
        Tink.Connector
      ],
      "HTTP & Networking": [
        Tink.HTTPBehaviour,
        Tink.HTTPAdapter,
        Tink.Retry
      ],
      Webhooks: [
        Tink.WebhookHandler,
        Tink.WebhookVerifier
      ],
      Utilities: [
        Tink.RateLimiter,
        Tink.Cache,
        Tink.Helpers
      ]
    ]
  end

  defp aliases do
    [
      # Setup
      setup: ["deps.get", "compile"],

      # Quality checks
      quality: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ],

      # Testing
      test: ["test"],
      "test.coverage": ["coveralls.html"],

      # Documentation
      docs: ["docs"],
      "docs.open": ["docs", "cmd open doc/index.html"],

      # CI
      ci: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "dialyzer",
        "test --cover"
      ]
    ]
  end
end
