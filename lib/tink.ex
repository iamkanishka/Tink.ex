defmodule Tink do
  @moduledoc """
  Production-grade Elixir client for the Tink Open Banking API.

  ## Installation

      {:tink, "~> 0.2"}

  ## Configuration

      config :tink,
        client_id: System.get_env("TINK_CLIENT_ID"),
        client_secret: System.get_env("TINK_CLIENT_SECRET"),
        webhook_secret: System.get_env("TINK_WEBHOOK_SECRET")

  ## Quick start

      {:ok, app_client} = Tink.app_client("authorization:grant user:create")
      {:ok, user_client} = Tink.user_client(redirect_code)
      {:ok, accounts}    = Tink.Accounts.list(user_client)
      all_txns = Tink.Transactions.stream(user_client) |> Enum.to_list()

  See individual module docs for full API coverage.
  """

  alias Tink.{Auth, Client, Error}

  @spec app_client(String.t(), keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def app_client(scope, opts \\ []) do
    Auth.client_credentials(Keyword.merge([scope: scope], opts))
  end

  @spec user_client(String.t(), keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def user_client(code, opts \\ []) do
    Auth.user_client(code, opts)
  end
end
