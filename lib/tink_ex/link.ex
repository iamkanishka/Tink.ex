defmodule TinkEx.Link do
  @moduledoc """
  Tink Link URL builder for user authentication flows.

  This module provides utilities for building Tink Link URLs for various
  use cases including:

  - Account aggregation
  - Payment initiation
  - Account verification
  - Income verification
  - Transaction access

  ## Features

  - **Multiple Products**: Support for all Tink products
  - **Customizable**: Market, locale, styling options
  - **Test Mode**: Testing without real credentials
  - **Redirect Handling**: Callback URL management

  ## Tink Link Products

  - **Transactions**: Account and transaction data
  - **Account Check**: Account ownership verification
  - **Income Check**: Income verification
  - **Payment Initiation**: Make payments
  - **Expense Check**: Expense analysis
  - **Risk Insights**: Risk assessment

  ## Use Cases

  ### Transaction Access

      def create_transactions_link(authorization_code, user_email) do
        TinkEx.Link.build_url(:transactions, %{
          client_id: get_client_id(),
          authorization_code: authorization_code,
          redirect_uri: "https://myapp.com/callback",
          market: "GB",
          locale: "en_US",
          test: false
        })
      end

  ### Account Verification

      def create_verification_link(authorization_code) do
        TinkEx.Link.build_url(:account_check, %{
          client_id: get_client_id(),
          authorization_code: authorization_code,
          redirect_uri: "https://myapp.com/verify/callback",
          market: "GB",
          locale: "en_US"
        })
      end

  ### Payment Initiation

      def create_payment_link(payment_request_id) do
        TinkEx.Link.build_url(:payment, %{
          client_id: get_client_id(),
          payment_request_id: payment_request_id,
          redirect_uri: "https://myapp.com/payment/callback",
          market: "SE",
          locale: "sv_SE"
        })
      end

  ## Markets

  - `GB` - United Kingdom
  - `SE` - Sweden
  - `DE` - Germany
  - `FR` - France
  - `ES` - Spain
  - `IT` - Italy
  - `NL` - Netherlands
  - `BE` - Belgium
  - `DK` - Denmark
  - `NO` - Norway
  - `FI` - Finland
  - `AT` - Austria
  - `PT` - Portugal

  ## Locales

  - `en_US` - English (US)
  - `en_GB` - English (UK)
  - `sv_SE` - Swedish
  - `da_DK` - Danish
  - `nb_NO` - Norwegian
  - `fi_FI` - Finnish
  - `de_DE` - German
  - `fr_FR` - French
  - `es_ES` - Spanish
  - `it_IT` - Italian
  - `nl_NL` - Dutch
  - `pt_PT` - Portuguese

  ## Links

  - [Tink Link Documentation](https://docs.tink.com/resources/tink-link)
  """

  @base_url "https://link.tink.com/1.0"

  @doc """
  Builds a Tink Link URL for the specified product.

  ## Parameters

    * `product` - Product type (atom):
      * `:transactions` - Transactions/account aggregation
      * `:account_check` - Account verification
      * `:income_check` - Income verification
      * `:payment` - Payment initiation
      * `:expense_check` - Expense check
      * `:risk_insights` - Risk insights
    * `params` - Link parameters:
      * `:client_id` - Your client ID (required)
      * `:redirect_uri` - Callback URL (required)
      * `:market` - Market code (required)
      * `:locale` - Locale code (required)
      * `:authorization_code` - Authorization code (for continuous access)
      * `:payment_request_id` - Payment request ID (for payments)
      * `:test` - Test mode (boolean, default: false)
      * `:input_provider` - Pre-select provider
      * `:input_username` - Pre-fill username (test mode only)

  ## Returns

    * Tink Link URL string

  ## Examples

      # Transactions (continuous access)
      url = TinkEx.Link.build_url(:transactions, %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback",
        authorization_code: "auth_code_123",
        market: "GB",
        locale: "en_US"
      })
      #=> "https://link.tink.com/1.0/transactions/connect-accounts?client_id=..."

      # Account Check
      url = TinkEx.Link.build_url(:account_check, %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/verify",
        authorization_code: "auth_code_456",
        market: "GB",
        locale: "en_US"
      })

      # Payment
      url = TinkEx.Link.build_url(:payment, %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/payment/done",
        payment_request_id: "payment_789",
        market: "SE",
        locale: "sv_SE"
      })

      # Test mode
      url = TinkEx.Link.build_url(:transactions, %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/test",
        authorization_code: "test_auth",
        market: "GB",
        locale: "en_US",
        test: true,
        input_provider: "testbank-gb",
        input_username: "testuser"
      })

  ## Product-specific Requirements

  ### Transactions
  - Requires: `authorization_code` (for continuous access) OR just client_id (for one-time)

  ### Account Check
  - Requires: `authorization_code`

  ### Income Check
  - Requires: `authorization_code`

  ### Payment
  - Requires: `payment_request_id`

  ### Expense Check
  - Requires: `authorization_code`

  ### Risk Insights
  - Requires: `authorization_code`
  """
  @spec build_url(atom(), map()) :: String.t()
  def build_url(product, params) when is_atom(product) and is_map(params) do
    path = get_product_path(product)
    query = build_query_params(product, params)

    "#{@base_url}/#{path}?#{URI.encode_query(query)}"
  end

  @doc """
  Builds a Tink Link URL for transactions (continuous access).

  Convenience function for the most common use case.

  ## Parameters

    * `authorization_code` - Authorization code from grant
    * `opts` - Link options:
      * `:client_id` - Your client ID (required)
      * `:redirect_uri` - Callback URL (required)
      * `:market` - Market code (required)
      * `:locale` - Locale code (required)
      * `:test` - Test mode (default: false)

  ## Returns

    * Tink Link URL string

  ## Examples

      url = TinkEx.Link.transactions_url("auth_code_123", %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback",
        market: "GB",
        locale: "en_US"
      })
  """
  @spec transactions_url(String.t(), map()) :: String.t()
  def transactions_url(authorization_code, opts) when is_binary(authorization_code) do
    params = Map.put(opts, :authorization_code, authorization_code)
    build_url(:transactions, params)
  end

  @doc """
  Builds a Tink Link URL for account verification.

  ## Parameters

    * `authorization_code` - Authorization code from grant
    * `opts` - Link options (same as build_url/2)

  ## Returns

    * Tink Link URL string

  ## Examples

      url = TinkEx.Link.account_check_url("auth_code_456", %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/verify",
        market: "GB",
        locale: "en_US"
      })
  """
  @spec account_check_url(String.t(), map()) :: String.t()
  def account_check_url(authorization_code, opts) when is_binary(authorization_code) do
    params = Map.put(opts, :authorization_code, authorization_code)
    build_url(:account_check, params)
  end

  @doc """
  Builds a Tink Link URL for payment initiation.

  ## Parameters

    * `payment_request_id` - Payment request ID
    * `opts` - Link options (same as build_url/2)

  ## Returns

    * Tink Link URL string

  ## Examples

      url = TinkEx.Link.payment_url("payment_789", %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/payment/done",
        market: "SE",
        locale: "sv_SE"
      })
  """
  @spec payment_url(String.t(), map()) :: String.t()
  def payment_url(payment_request_id, opts) when is_binary(payment_request_id) do
    params = Map.put(opts, :payment_request_id, payment_request_id)
    build_url(:payment, params)
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp get_product_path(:transactions), do: "transactions/connect-accounts"
  defp get_product_path(:account_check), do: "account-check/connect-accounts"
  defp get_product_path(:income_check), do: "income-check/connect-accounts"
  defp get_product_path(:payment), do: "pay/execute-payment"
  defp get_product_path(:expense_check), do: "expense-check/connect-accounts"
  defp get_product_path(:risk_insights), do: "risk-insights/connect-accounts"

  defp build_query_params(product, params) do
    base_params = %{
      "client_id" => Map.fetch!(params, :client_id),
      "redirect_uri" => Map.fetch!(params, :redirect_uri),
      "market" => Map.fetch!(params, :market),
      "locale" => Map.fetch!(params, :locale)
    }

    base_params
    |> add_authorization_code(params)
    |> add_payment_request_id(product, params)
    |> add_test_params(params)
    |> add_optional_params(params)
  end

  defp add_authorization_code(query, %{authorization_code: code}) when is_binary(code) do
    Map.put(query, "authorization_code", code)
  end

  defp add_authorization_code(query, _params), do: query

  defp add_payment_request_id(query, :payment, %{payment_request_id: id}) when is_binary(id) do
    Map.put(query, "payment_request_id", id)
  end

  defp add_payment_request_id(query, _product, _params), do: query

  defp add_test_params(query, %{test: true}) do
    query
    |> Map.put("test", "true")
    |> maybe_add_test_provider(Map.get(params, :input_provider))
    |> maybe_add_test_username(Map.get(params, :input_username))
  end

  defp add_test_params(query, _params), do: query

  defp maybe_add_test_provider(query, nil), do: query
  defp maybe_add_test_provider(query, provider), do: Map.put(query, "input_provider", provider)

  defp maybe_add_test_username(query, nil), do: query
  defp maybe_add_test_username(query, username), do: Map.put(query, "input_username", username)

  defp add_optional_params(query, params) do
    query
    |> maybe_add_param("state", params[:state])
    |> maybe_add_param("iframe", params[:iframe])
  end

  defp maybe_add_param(query, _key, nil), do: query
  defp maybe_add_param(query, key, value), do: Map.put(query, key, to_string(value))
end
