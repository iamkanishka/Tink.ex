defmodule TinkEx.Budgets do
  @moduledoc """
  Business Finance Management (BFM) Budgets API.

  Comprehensive budget management for business financial planning with support for
  one-off and recurring budgets, progress tracking, and budget history.

  ## Features

  - **One-off Budgets**: Single-period budgets
  - **Recurring Budgets**: Monthly, quarterly, or yearly budgets
  - **Progress Tracking**: Monitor budget performance
  - **Budget History**: View historical budget data
  - **Allocation Rules**: Category, account, and tag-based allocation

  ## Prerequisites

  - Generated user with bearer token (user authentication token)
  - Accounts created and linked to user
  - (Optional) Transactions ingested for budget tracking

  ## Quick Start

      # Create client with user bearer token
      client = TinkEx.client(access_token: user_bearer_token)

      # Create budget
      {:ok, budget} = TinkEx.Budgets.create_budget(client, %{
        title: "Marketing Q1",
        type: "EXPENSE",
        target_amount: %{
          value: %{unscaled_value: 50000, scale: 0},
          currency_code: "SEK"
        },
        recurrence: %{
          frequency: "MONTHLY",
          start: "2024-01-01",
          end: "2024-03-31"
        },
        allocation_rules: %{
          expense_allocation_rules: [
            %{
              categories: [%{id: "marketing-category-id"}],
              accounts: [%{id: "account-id"}],
              tags: []
            }
          ],
          income_allocation_rules: []
        }
      })
  """

  alias TinkEx.{Client, Error, Helpers}

  @doc """
  Creates a new business budget.

  ## Required Scope

  User bearer token (not client credentials)

  ## Examples

      {:ok, budget} = TinkEx.Budgets.create_budget(client, %{
        title: "Test budget",
        description: "Test budget's description",
        type: "INCOME",
        target_amount: %{
          value: %{unscaled_value: 123, scale: 0},
          currency_code: "SEK"
        },
        recurrence: %{
          frequency: "ONE_OFF",
          start: "2021-07-01",
          end: "2021-07-31"
        },
        allocation_rules: %{
          expense_allocation_rules: [],
          income_allocation_rules: [
            %{
              categories: [%{id: "category-id"}],
              accounts: [%{id: "account-id"}],
              tags: []
            }
          ]
        }
      })
  """
  @spec create_budget(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_budget(%Client{} = client, params) when is_map(params) do
    url = "/finance-management/v1/business-budgets"
    Client.post(client, url, params)
  end

  @doc """
  Gets details for a specific budget.

  ## Examples

      {:ok, budget} = TinkEx.Budgets.get_budget(client, "budget_id")
  """
  @spec get_budget(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_budget(%Client{} = client, budget_id) when is_binary(budget_id) do
    url = "/finance-management/v1/business-budgets/#{budget_id}"
    Client.get(client, url)
  end

  @doc """
  Gets the history of a budget across all periods.

  ## Examples

      {:ok, history} = TinkEx.Budgets.get_budget_history(client, "budget_id")
  """
  @spec get_budget_history(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_budget_history(%Client{} = client, budget_id) when is_binary(budget_id) do
    url = "/finance-management/v1/business-budgets/#{budget_id}/history"
    Client.get(client, url)
  end

  @doc """
  Lists all business budgets with optional filtering.

  ## Examples

      {:ok, budgets} = TinkEx.Budgets.list_budgets(client)
      {:ok, on_track} = TinkEx.Budgets.list_budgets(client, progress_status_in: ["ON_TRACK"])
  """
  @spec list_budgets(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_budgets(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/finance-management/v1/business-budgets", opts)
    Client.get(client, url)
  end

  @doc """
  Updates an existing budget.

  ## Examples

      {:ok, updated} = TinkEx.Budgets.update_budget(client, "budget_id", %{
        title: "New title",
        target_amount: %{
          value: %{unscaled_value: 1000000, scale: 0},
          currency_code: "SEK"
        }
      })
  """
  @spec update_budget(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update_budget(%Client{} = client, budget_id, updates)
      when is_binary(budget_id) and is_map(updates) do
    url = "/finance-management/v1/business-budgets/#{budget_id}"
    Client.patch(client, url, updates)
  end

  @doc """
  Deletes a budget.

  ## Examples

      :ok = TinkEx.Budgets.delete_budget(client, "budget_id")
  """
  @spec delete_budget(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_budget(%Client{} = client, budget_id) when is_binary(budget_id) do
    url = "/finance-management/v1/business-budgets/#{budget_id}"

    case Client.delete(client, url) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end
end
