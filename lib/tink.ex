defmodule Tink do
  @moduledoc """
  Tink - Elixir client for the Tink API.

  Tink provides a comprehensive, production-ready interface to the Tink API,
  enabling access to financial data, account verification, and insights across
  3,500+ financial institutions in Europe.

  ## Quick Start

      # Create a client
      client = Tink.client()

      # List providers
      {:ok, providers} = Tink.Providers.list_providers(client, market: "GB")

      # Account verification
      {:ok, report} = Tink.AccountCheck.create_report(client, %{
        external_user_id: "user_123",
        account_number: "12345678",
        sort_code: "12-34-56"
      })

  ## Configuration

      # config/config.exs
      config :tink,
        client_id: System.get_env("TINK_CLIENT_ID"),
        client_secret: System.get_env("TINK_CLIENT_SECRET"),
        base_url: "https://api.tink.com"

  ## Features

  - **Account Aggregation** - Access to accounts and transactions
  - **Verification** - Account, income, expense, and balance verification
  - **Risk Assessment** - Risk insights and categorization
  - **Financial Management** - Budgets, investments, loans
  - **High Performance** - Built-in caching and connection pooling
  - **Production Ready** - Comprehensive error handling and retries

  ## Products

  ### Verification Products
  - `Tink.AccountCheck` - Verify account ownership
  - `Tink.IncomeCheck` - Verify income
  - `Tink.ExpenseCheck` - Analyze expenses
  - `Tink.BalanceCheck` - Check account balances
  - `Tink.BusinessAccountCheck` - Business account verification

  ### Data Products
  - `Tink.Transactions` - Transaction data
  - `Tink.Accounts` - Account information
  - `Tink.Statistics` - Financial statistics

  ### Insights Products
  - `Tink.RiskInsights` - Risk assessment
  - `Tink.RiskCategorisation` - Risk categorization
  - `Tink.CashFlow` - Cash flow analysis

  ### Management Products
  - `Tink.Budgets` - Budget management
  - `Tink.Investments` - Investment tracking
  - `Tink.Loans` - Loan management
  - `Tink.FinancialCalendar` - Financial calendar

  ### Infrastructure
  - `Tink.Providers` - Financial institution providers
  - `Tink.Users` - User management
  - `Tink.Categories` - Transaction categories
  - `Tink.Link` - Tink Link URL builder
  - `Tink.Connectivity` - Provider connectivity monitoring

  ## Links

  - [Tink Documentation](https://docs.tink.com)
  - [API Reference](https://api-reference.tink.com)
  - [Tink Console](https://console.tink.com)
  """

  alias Tink.{Client, Config}

  @doc """
  Creates a Tink client for API requests.

  ## Options

    * `:client_id` - Tink client ID (defaults to config)
    * `:client_secret` - Tink client secret (defaults to config)
    * `:base_url` - API base URL (defaults to config)
    * `:access_token` - User access token (for user-specific requests)
    * `:user_id` - User ID (for cache invalidation)
    * `:timeout` - Request timeout in milliseconds
    * `:cache` - Enable/disable caching (default: true)
    * `:adapter` - HTTP adapter module (for testing)

  ## Examples

      # Platform client (for provider/category data)
      client = Tink.client()
      {:ok, providers} = Tink.Providers.list_providers(client)

      # User client (for user-specific data)
      user_client = Tink.client(access_token: "user_token_123")
      {:ok, accounts} = Tink.Accounts.list_accounts(user_client)

      # Custom configuration
      client = Tink.client(
        client_id: "custom_client_id",
        client_secret: "custom_secret",
        timeout: 60_000
      )

      # Disable caching for a specific client
      client = Tink.client(cache: false)

      # Testing with mock adapter
      client = Tink.client(adapter: MyApp.MockHTTPAdapter)

  ## Authentication

  For platform operations (providers, categories), use a client without
  an access token. For user data (accounts, transactions), provide a
  user access token obtained through Tink Link or the OAuth flow.
  """
  @spec client(keyword()) :: Client.t()
  def client(opts \\ []) do
    %Client{
      base_url: Keyword.get(opts, :base_url, Config.get(:base_url)),
      client_id: Keyword.get(opts, :client_id, Config.get(:client_id)),
      client_secret: Keyword.get(opts, :client_secret, Config.get(:client_secret)),
      access_token: Keyword.get(opts, :access_token),
      user_id: Keyword.get(opts, :user_id),
      timeout: Keyword.get(opts, :timeout, Config.get(:timeout, 30_000)),
      adapter: Keyword.get(opts, :adapter, Config.get(:http_adapter, Tink.HTTPAdapter)),
      cache: Keyword.get(opts, :cache, true)
    }
  end

  @doc """
  Returns the current Tink version.

  ## Examples

      Tink.version()
      #=> "1.0.0"
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:tink, :vsn)
    |> to_string()
  end

  @doc """
  Checks if Tink is properly configured.

  Returns `:ok` if configuration is valid, otherwise returns an error tuple.

  ## Examples

      case Tink.check_config() do
        :ok ->
          IO.puts("Tink is properly configured")

        {:error, :missing_client_id} ->
          IO.puts("Missing TINK_CLIENT_ID")

        {:error, :missing_client_secret} ->
          IO.puts("Missing TINK_CLIENT_SECRET")
      end
  """
  @spec check_config() :: :ok | {:error, :missing_base_url | :missing_client_id | :missing_client_secret}
  def check_config do
    cond do
      is_nil(Config.get(:client_id)) ->
        {:error, :missing_client_id}

      is_nil(Config.get(:client_secret)) ->
        {:error, :missing_client_secret}

      is_nil(Config.get(:base_url)) ->
        {:error, :missing_base_url}

      true ->
        :ok
    end
  end

  @doc """
  Returns information about the current Tink configuration.

  Useful for debugging and verifying configuration in different environments.

  ## Examples

      info = Tink.info()
      IO.inspect(info)
      #=> %{
      #     version: "1.0.0",
      #     base_url: "https://api.tink.com",
      #     cache_enabled: true,
      #     retry_enabled: true,
      #     timeout: 30000
      #   }
  """
  @spec info() :: %{
          adapter: term(),
          base_url: term(),
          cache_enabled: term(),
          retry_enabled: term(),
          timeout: term(),
          version: String.t()
        }
  def info do
    %{
      version: version(),
      base_url: Config.get(:base_url),
      cache_enabled: get_in(Config.get(:cache, []), [:enabled]) || false,
      retry_enabled: get_in(Config.get(:retry, []), [:enabled]) || false,
      timeout: Config.get(:timeout, 30_000),
      adapter: Config.get(:http_adapter, Tink.HTTPAdapter)
    }
  end
end
