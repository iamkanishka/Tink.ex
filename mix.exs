defmodule TinkAPI.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/yourusername/tink_api"

  def project do
    [
      app: :tink_api,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "TinkAPI",
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:ex_unit, :mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {TinkAPI.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # HTTP client
      {:finch, "~> 0.18"},
      {:jason, "~> 1.4"},
      {:mint, "~> 1.5"},

      # OAuth & JWT
      {:oauth2, "~> 2.1"},
      {:joken, "~> 2.6"},

      # Utilities
      {:telemetry, "~> 1.2"},
      {:retry, "~> 0.18"},
      {:nimble_options, "~> 1.0"},

      # Development & Testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},

      # Testing
      {:mox, "~> 1.1", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:stream_data, "~> 0.6", only: :test}
    ]
  end

  defp description do
    """
    Complete Elixir client for Tink's open banking platform.
    Access financial data from 6000+ European banks and institutions through a single API.
    """
  end

  defp package do
    [
      name: "tink_api",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Tink Documentation" => "https://docs.tink.com",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Your Name"]
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
        "guides/getting_started.md",
        "guides/authentication.md",
        "guides/products/account_check.md",
        "guides/products/income_check.md",
        "guides/products/transactions.md",
        "guides/error_handling.md"
      ],
      groups_for_extras: [
        "Guides": ~r/guides\/.*/,
        "Products": ~r/guides\/products\/.*/
      ],
      groups_for_modules: [
        "Core": [
          TinkAPI,
          TinkAPI.Client,
          TinkAPI.Config
        ],
        "Authentication": [
          TinkAPI.Auth.OAuth,
          TinkAPI.Auth.TokenManager
        ],
        "Resources": [
          TinkAPI.Resources.AccountCheck,
          TinkAPI.Resources.IncomeCheck,
          TinkAPI.Resources.Transactions,
          TinkAPI.Resources.BalanceCheck,
          TinkAPI.Resources.ExpenseCheck,
          TinkAPI.Resources.RiskInsights,
          TinkAPI.Resources.Budgets,
          TinkAPI.Resources.CashFlow,
          TinkAPI.Resources.Investments,
          TinkAPI.Resources.Loans,
          TinkAPI.Resources.Connectivity,
          TinkAPI.Resources.Connectors
        ],
        "Webhooks": [
          TinkAPI.Webhooks.Handler,
          TinkAPI.Webhooks.Verifier
        ],
        "Utilities": [
          TinkAPI.Error,
          TinkAPI.Utils.Retry,
          TinkAPI.Utils.RateLimiter,
          TinkAPI.Utils.Helpers
        ]
      ]
    ]
  end
end
