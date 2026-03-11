defmodule TinkEx.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/yourusername/tink_ex"

  def project do
    [
      app: :tink_ex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "TinkEx",
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
      extra_applications: [:logger, :crypto, :ssl],
      mod: {TinkEx.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP client (Production)
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
      {:hammer, "~> 7.1", optional: true},

      # Development & Documentation
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
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
    Production-ready Elixir client for the Tink API. Provides comprehensive
    access to account aggregation, transaction data, financial insights,
    account verification, income verification, and payment initiation services.
    """
  end

  defp package do
    [
      name: "tink_ex",
      files: ~w(
        lib
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
      ),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/tink_ex"
      },
      maintainers: ["Your Name <your.email@example.com>"]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "TinkEx",
      source_ref: "v#{@version}",
      canonical: "https://hexdocs.pm/tink_ex",
      source_url: @source_url,
      logo: "assets/logo.png",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      groups_for_functions: [
        "API Resources": &(&1[:section] == :api),
        "Configuration": &(&1[:section] == :config),
        "Utilities": &(&1[:section] == :util)
      ]
    ]
  end

  defp extras do
    [
      # Main documentation
      "README.md",
      "CHANGELOG.md",
      "LICENSE",

      # Guides
      "guides/getting-started.md",
      "guides/authentication.md",
      "guides/configuration.md",

      # Product guides
      "guides/products/account-check.md",
      "guides/products/transactions.md",
      "guides/products/income-check.md",
      "guides/products/expense-check.md",
      "guides/products/risk-insights.md",
      "guides/products/payments.md",

      # Advanced guides
      "guides/advanced/error-handling.md",
      "guides/advanced/testing.md",
      "guides/advanced/rate-limiting.md",
      "guides/advanced/caching.md",
      "guides/advanced/telemetry.md"
    ]
  end

  defp groups_for_extras do
    [
      "Getting Started": ~r/guides\/(getting-started|authentication|configuration)/,
      "Products": ~r/guides\/products/,
      "Advanced": ~r/guides\/advanced/
    ]
  end

  defp groups_for_modules do
    [
      "Core": [
        TinkEx,
        TinkEx.Client,
        TinkEx.Config,
        TinkEx.Auth,
        TinkEx.Error
      ],

      "Account Aggregation": [
        TinkEx.Transactions,
        TinkEx.TransactionsOneTimeAccess,
        TinkEx.TransactionsContinuousAccess,
        TinkEx.Accounts,
        TinkEx.Users,
        TinkEx.Categories,
        TinkEx.Statistics
      ],

      "Verification & Insights": [
        TinkEx.AccountCheck,
        TinkEx.IncomeCheck,
        TinkEx.ExpenseCheck,
        TinkEx.RiskCategorisation,
        TinkEx.RiskInsights,
        TinkEx.BusinessAccountCheck,
        TinkEx.BalanceCheck
      ],

      "Finance Management": [
        TinkEx.Budgets,
        TinkEx.CashFlow,
        TinkEx.FinancialCalendar
      ],

      "Investment & Loans": [
        TinkEx.Investments,
        TinkEx.Loans
      ],

      "Infrastructure": [
        TinkEx.Providers,
        TinkEx.Connectivity,
        TinkEx.Link
      ],

      "HTTP & Networking": [
        TinkEx.HTTPBehaviour,
        TinkEx.HTTPAdapter,
        TinkEx.Retry
      ],

      "Utilities": [
        TinkEx.RateLimiter,
        TinkEx.Cache,
        TinkEx.Helpers,
        TinkEx.Connector
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
      "test.watch": ["test.watch"],

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
