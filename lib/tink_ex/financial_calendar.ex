defmodule TinkEx.FinancialCalendar do
  @moduledoc """
  Financial Calendar API for managing scheduled financial events.

  This module provides comprehensive financial calendar management for tracking:
  - Upcoming bills and payments
  - Income events (salary, invoices)
  - Recurring financial events
  - Event reconciliation with actual transactions
  - Calendar summaries and overviews

  ## Features

  - **Event Management**: Create, update, delete financial events
  - **Recurring Events**: Support for recurring patterns (daily, weekly, monthly)
  - **Attachments**: Add documents/links to events (invoices, receipts)
  - **Reconciliation**: Match events with actual transactions
  - **Summaries**: Get calendar overviews by time period
  - **Suggestions**: AI-powered reconciliation suggestions

  ## Prerequisites

  - Generated user with bearer token
  - Accounts created and linked to user
  - (Optional) Transactions ingested for reconciliation

  ## Flow Overview

      # Create client with user bearer token
      client = TinkEx.client(access_token: user_bearer_token)

      # Create a bill event
      {:ok, event} = TinkEx.FinancialCalendar.create_event(client, %{
        title: "Electricity Bill",
        description: "Monthly electricity payment",
        due_date: "2024-02-15",
        event_amount: %{
          currency_code: "EUR",
          value: %{unscaled_value: 12500, scale: 2}  # €125.00
        }
      })

      # Get event details
      {:ok, details} = TinkEx.FinancialCalendar.get_event(client, event["id"])

      # Add attachment (invoice PDF)
      {:ok, attachment} = TinkEx.FinancialCalendar.add_attachment(client, event["id"], %{
        title: "Invoice February 2024",
        url: "https://storage.example.com/invoice.pdf"
      })

      # Create recurring event
      {:ok, recurring} = TinkEx.FinancialCalendar.create_recurring_group(
        client,
        event["id"],
        %{rrule_pattern: "FREQ=MONTHLY;COUNT=12"}
      )

      # List upcoming events
      {:ok, events} = TinkEx.FinancialCalendar.list_events(client,
        due_date_gte: "2024-02-01",
        due_date_lte: "2024-02-29"
      )

      # Get calendar summary
      {:ok, summary} = TinkEx.FinancialCalendar.get_summaries(client,
        resolution: "WEEKLY",
        period_gte: "2024-02-01",
        period_lte: "2024-02-29"
      )

      # Reconcile with transaction
      {:ok, reconciliation} = TinkEx.FinancialCalendar.create_reconciliation(
        client,
        event["id"],
        %{transaction_id: "txn_123"}
      )

  ## Use Cases

  ### Bill Tracking

      def track_monthly_bills(client) do
        bills = [
          {"Rent", "2024-02-01", 150000},
          {"Electricity", "2024-02-15", 8500},
          {"Internet", "2024-02-20", 4999}
        ]

        Enum.map(bills, fn {title, due_date, amount} ->
          TinkEx.FinancialCalendar.create_event(client, %{
            title: title,
            due_date: due_date,
            event_amount: money_amount(amount, "EUR")
          })
        end)
      end

  ### Salary Tracking

      def setup_salary_events(client, monthly_salary) do
        # Create first salary event
        {:ok, event} = TinkEx.FinancialCalendar.create_event(client, %{
          title: "Monthly Salary",
          due_date: next_salary_date(),
          event_amount: money_amount(monthly_salary, "EUR")
        })

        # Make it recurring (monthly for a year)
        TinkEx.FinancialCalendar.create_recurring_group(client, event["id"], %{
          rrule_pattern: "FREQ=MONTHLY;COUNT=12"
        })
      end

  ### Budget Planning

      def get_upcoming_obligations(client, days \\ 30) do
        start_date = Date.to_iso8601(Date.utc_today())
        end_date = Date.add(Date.utc_today(), days) |> Date.to_iso8601()

        {:ok, events} = TinkEx.FinancialCalendar.list_events(client,
          due_date_gte: start_date,
          due_date_lte: end_date
        )

        total = calculate_total_amount(events["events"])

        %{
          event_count: length(events["events"]),
          total_amount: total,
          events: events["events"]
        }
      end

  ## Recurring Patterns

  Uses RFC 5545 RRULE format:

  - **Daily**: `FREQ=DAILY;COUNT=30`
  - **Weekly**: `FREQ=WEEKLY;COUNT=52`
  - **Monthly**: `FREQ=MONTHLY;COUNT=12`
  - **Yearly**: `FREQ=YEARLY;COUNT=5`
  - **Every 2 weeks**: `FREQ=WEEKLY;INTERVAL=2;COUNT=26`

  ## Required Scope

  User bearer token (user authentication, not client credentials)

  ## Links

  - [Financial Calendar API](https://docs.tink.com/api#finance-management/cash-flow)
  - [Finance Management Guide](https://docs.tink.com/resources/finance-management)
  """

  alias TinkEx.{Client, Error, Helpers}

  # ---------------------------------------------------------------------------
  # Event Management
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new financial calendar event.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `params` - Event parameters:
      * `:title` - Event title (required)
      * `:due_date` - Due date (ISO-8601: "YYYY-MM-DD") (required)
      * `:event_amount` - Amount (required):
        * `:currency_code` - Currency code (e.g., "EUR", "USD")
        * `:value` - Amount value:
          * `:unscaled_value` - Amount in smallest unit
          * `:scale` - Decimal places
      * `:description` - Event description (optional)

  ## Returns

    * `{:ok, event}` - Created event with `id`
    * `{:error, error}` - If the request fails

  ## Examples

      # Create a bill event
      {:ok, event} = TinkEx.FinancialCalendar.create_event(client, %{
        title: "Electricity Bill",
        description: "Monthly electricity payment",
        due_date: "2024-02-15",
        event_amount: %{
          currency_code: "EUR",
          value: %{
            unscaled_value: 12500,
            scale: 2  # €125.00
          }
        }
      })
      #=> {:ok, %{
      #     "id" => "event_abc123",
      #     "title" => "Electricity Bill",
      #     "description" => "Monthly electricity payment",
      #     "dueDate" => "2024-02-15",
      #     "eventAmount" => %{
      #       "currencyCode" => "EUR",
      #       "value" => %{"unscaledValue" => 12500, "scale" => 2}
      #     },
      #     "reconciled" => false
      #   }}

      # Create income event
      {:ok, salary} = TinkEx.FinancialCalendar.create_event(client, %{
        title: "Monthly Salary",
        due_date: "2024-02-28",
        event_amount: %{
          currency_code: "EUR",
          value: %{unscaled_value: 350000, scale: 2}  # €3,500.00
        }
      })
  """
  @spec create_event(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_event(%Client{} = client, params) when is_map(params) do
    url = "/finance-management/v1/financial-calendar-events"

    body =
      %{
        "title" => Map.fetch!(params, :title),
        "dueDate" => Map.fetch!(params, :due_date),
        "eventAmount" => Map.fetch!(params, :event_amount)
      }
      |> maybe_add_field("description", params[:description])

    Client.post(client, url, body)
  end

  @doc """
  Gets details for a specific calendar event.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID

  ## Returns

    * `{:ok, event}` - Event details
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, event} = TinkEx.FinancialCalendar.get_event(client, "event_abc123")
      #=> {:ok, %{
      #     "id" => "event_abc123",
      #     "title" => "Electricity Bill",
      #     "dueDate" => "2024-02-15",
      #     "eventAmount" => %{...},
      #     "reconciled" => false,
      #     "attachments" => [],
      #     "recurringGroup" => nil
      #   }}
  """
  @spec get_event(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_event(%Client{} = client, event_id) when is_binary(event_id) do
    url = "/finance-management/v1/financial-calendar-events/#{event_id}"

    Client.get(client, url)
  end

  @doc """
  Updates a calendar event.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID
    * `updates` - Fields to update:
      * `:title` - New title (optional)
      * `:description` - New description (optional)
      * `:event_amount` - New amount (optional)

  ## Returns

    * `{:ok, event}` - Updated event
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, updated} = TinkEx.FinancialCalendar.update_event(
        client,
        "event_abc123",
        %{
          description: "Updated description",
          event_amount: %{
            currency_code: "EUR",
            value: %{unscaled_value: 13000, scale: 2}
          }
        }
      )
  """
  @spec update_event(Client.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_event(%Client{} = client, event_id, updates)
      when is_binary(event_id) and is_map(updates) do
    url = "/finance-management/v1/financial-calendar-events/#{event_id}"

    body = build_update_body(updates)

    Client.patch(client, url, body)
  end

  @doc """
  Lists calendar events with optional filtering.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `opts` - Query options:
      * `:due_date_gte` - Due date >= (ISO-8601: "YYYY-MM-DD")
      * `:due_date_lte` - Due date <= (ISO-8601: "YYYY-MM-DD")
      * `:account_id_in` - Filter by account IDs (list)

  ## Returns

    * `{:ok, events}` - List of events
    * `{:error, error}` - If the request fails

  ## Examples

      # List events for February
      {:ok, events} = TinkEx.FinancialCalendar.list_events(client,
        due_date_gte: "2024-02-01",
        due_date_lte: "2024-02-29"
      )
      #=> {:ok, %{
      #     "events" => [
      #       %{"id" => "event_1", "title" => "Rent", ...},
      #       %{"id" => "event_2", "title" => "Electricity", ...}
      #     ]
      #   }}

      # List upcoming events (next 30 days)
      {:ok, upcoming} = TinkEx.FinancialCalendar.list_events(client,
        due_date_gte: Date.to_iso8601(Date.utc_today()),
        due_date_lte: Date.add(Date.utc_today(), 30) |> Date.to_iso8601()
      )

      # Filter by account
      {:ok, account_events} = TinkEx.FinancialCalendar.list_events(client,
        due_date_gte: "2024-01-01",
        due_date_lte: "2024-12-31",
        account_id_in: ["account_1", "account_2"]
      )
  """
  @spec list_events(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_events(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/finance-management/v1/financial-calendar-events", opts)

    Client.get(client, url)
  end

  @doc """
  Deletes a calendar event.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID
    * `opts` - Delete options:
      * `:recurring` - How to handle recurring: "SINGLE", "ALL", "FUTURE"

  ## Returns

    * `:ok` - Event deleted successfully
    * `{:error, error}` - If the request fails

  ## Examples

      # Delete single event
      :ok = TinkEx.FinancialCalendar.delete_event(client, "event_abc123",
        recurring: "SINGLE"
      )

      # Delete all events in recurring group
      :ok = TinkEx.FinancialCalendar.delete_event(client, "event_abc123",
        recurring: "ALL"
      )

      # Delete this and future events
      :ok = TinkEx.FinancialCalendar.delete_event(client, "event_abc123",
        recurring: "FUTURE"
      )
  """
  @spec delete_event(Client.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def delete_event(%Client{} = client, event_id, opts \\ [])
      when is_binary(event_id) do
    recurring = Keyword.get(opts, :recurring, "SINGLE")
    url = "/finance-management/v1/financial-calendar-events/#{event_id}/?recurring=#{recurring}"

    case Client.delete(client, url) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Calendar Summaries
  # ---------------------------------------------------------------------------

  @doc """
  Gets calendar summaries for a period with specified resolution.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `opts` - Query options:
      * `:resolution` - Time resolution: "WEEKLY", "MONTHLY" (required)
      * `:period_gte` - Period start (ISO-8601: "YYYY-MM-DD") (required)
      * `:period_lte` - Period end (ISO-8601: "YYYY-MM-DD") (required)
      * `:account_id_in` - Filter by accounts (list) (optional)

  ## Returns

    * `{:ok, summaries}` - Calendar summaries
    * `{:error, error}` - If the request fails

  ## Examples

      # Get weekly summaries
      {:ok, weekly} = TinkEx.FinancialCalendar.get_summaries(client,
        resolution: "WEEKLY",
        period_gte: "2024-02-01",
        period_lte: "2024-02-29"
      )
      #=> {:ok, %{
      #     "resolution" => "WEEKLY",
      #     "periods" => [
      #       %{
      #         "periodStart" => "2024-02-01",
      #         "periodEnd" => "2024-02-07",
      #         "totalAmount" => %{
      #           "currencyCode" => "EUR",
      #           "value" => %{"unscaledValue" => 45000, "scale" => 2}
      #         },
      #         "eventCount" => 3
      #       },
      #       ...
      #     ]
      #   }}

      # Get monthly summaries for the year
      {:ok, monthly} = TinkEx.FinancialCalendar.get_summaries(client,
        resolution: "MONTHLY",
        period_gte: "2024-01-01",
        period_lte: "2024-12-31"
      )
  """
  @spec get_summaries(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_summaries(%Client{} = client, opts) do
    resolution = Keyword.fetch!(opts, :resolution)
    period_gte = Keyword.fetch!(opts, :period_gte)
    period_lte = Keyword.fetch!(opts, :period_lte)

    query_params =
      [
        {:period_gte, period_gte},
        {:period_lte, period_lte}
      ]
      |> maybe_add_param(:account_id_in, opts[:account_id_in])

    url = Helpers.build_url(
      "/finance-management/v1/financial-calendar-summaries/#{resolution}",
      query_params
    )

    Client.get(client, url)
  end

  # ---------------------------------------------------------------------------
  # Attachments
  # ---------------------------------------------------------------------------

  @doc """
  Adds an attachment to a calendar event.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID
    * `params` - Attachment parameters:
      * `:title` - Attachment title (required)
      * `:url` - Attachment URL (required)

  ## Returns

    * `{:ok, attachment}` - Created attachment with `id`
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, attachment} = TinkEx.FinancialCalendar.add_attachment(
        client,
        "event_abc123",
        %{
          title: "Invoice February 2024",
          url: "https://storage.example.com/invoices/feb-2024.pdf"
        }
      )
      #=> {:ok, %{
      #     "id" => "attachment_xyz",
      #     "title" => "Invoice February 2024",
      #     "url" => "https://storage.example.com/invoices/feb-2024.pdf"
      #   }}
  """
  @spec add_attachment(Client.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_attachment(%Client{} = client, event_id, params)
      when is_binary(event_id) and is_map(params) do
    url = "/finance-management/v1/financial-calendar-events/#{event_id}/attachments"

    body = %{
      "title" => Map.fetch!(params, :title),
      "url" => Map.fetch!(params, :url)
    }

    Client.post(client, url, body)
  end

  @doc """
  Deletes an attachment from a calendar event.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID
    * `attachment_id` - Attachment ID

  ## Returns

    * `:ok` - Attachment deleted successfully
    * `{:error, error}` - If the request fails

  ## Examples

      :ok = TinkEx.FinancialCalendar.delete_attachment(
        client,
        "event_abc123",
        "attachment_xyz"
      )
  """
  @spec delete_attachment(Client.t(), String.t(), String.t()) ::
          :ok | {:error, Error.t()}
  def delete_attachment(%Client{} = client, event_id, attachment_id)
      when is_binary(event_id) and is_binary(attachment_id) do
    url =
      "/finance-management/v1/financial-calendar-events/#{event_id}/attachments/#{attachment_id}/"

    case Client.delete(client, url) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Recurring Events
  # ---------------------------------------------------------------------------

  @doc """
  Creates a recurring group for an event.

  Uses RFC 5545 RRULE format to define recurrence pattern.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID (becomes first event in recurring series)
    * `params` - Recurring parameters:
      * `:rrule_pattern` - RRULE pattern string (required)

  ## Returns

    * `{:ok, recurring_group}` - Created recurring group
    * `{:error, error}` - If the request fails

  ## Examples

      # Daily for 10 days
      {:ok, group} = TinkEx.FinancialCalendar.create_recurring_group(
        client,
        "event_abc123",
        %{rrule_pattern: "FREQ=DAILY;INTERVAL=10;COUNT=5"}
      )

      # Weekly for a year
      {:ok, group} = TinkEx.FinancialCalendar.create_recurring_group(
        client,
        "event_abc123",
        %{rrule_pattern: "FREQ=WEEKLY;COUNT=52"}
      )

      # Monthly for a year
      {:ok, group} = TinkEx.FinancialCalendar.create_recurring_group(
        client,
        "event_abc123",
        %{rrule_pattern: "FREQ=MONTHLY;COUNT=12"}
      )

      # Every 2 weeks for 6 months
      {:ok, group} = TinkEx.FinancialCalendar.create_recurring_group(
        client,
        "event_abc123",
        %{rrule_pattern: "FREQ=WEEKLY;INTERVAL=2;COUNT=13"}
      )

  ## RRULE Pattern Format

  Common patterns:
  - `FREQ=DAILY;COUNT=30` - Daily for 30 days
  - `FREQ=WEEKLY;COUNT=52` - Weekly for a year
  - `FREQ=MONTHLY;COUNT=12` - Monthly for a year
  - `FREQ=YEARLY;COUNT=5` - Yearly for 5 years
  - `FREQ=DAILY;INTERVAL=2;COUNT=15` - Every 2 days, 15 times
  """
  @spec create_recurring_group(Client.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_recurring_group(%Client{} = client, event_id, params)
      when is_binary(event_id) and is_map(params) do
    url = "/finance-management/v1/financial-calendar-events/#{event_id}/recurring-group"

    body = %{
      "rrulePattern" => Map.fetch!(params, :rrule_pattern)
    }

    Client.post(client, url, body)
  end

  # ---------------------------------------------------------------------------
  # Reconciliation
  # ---------------------------------------------------------------------------

  @doc """
  Creates a reconciliation between an event and a transaction.

  Links a calendar event with an actual transaction to mark it as paid/received.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID
    * `params` - Reconciliation parameters:
      * `:transaction_id` - Transaction ID to link (required)

  ## Returns

    * `{:ok, reconciliation}` - Created reconciliation
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, reconciliation} = TinkEx.FinancialCalendar.create_reconciliation(
        client,
        "event_abc123",
        %{transaction_id: "9b2c283a73ba49679798cb2105571661"}
      )
      #=> {:ok, %{
      #     "eventId" => "event_abc123",
      #     "transactionId" => "9b2c283a73ba49679798cb2105571661",
      #     "reconciledAt" => "2024-02-15T10:30:00Z"
      #   }}
  """
  @spec create_reconciliation(Client.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_reconciliation(%Client{} = client, event_id, params)
      when is_binary(event_id) and is_map(params) do
    url = "/finance-management/v1/financial-calendar-events/#{event_id}/reconciliations"

    body = %{
      "transaction_id" => Map.fetch!(params, :transaction_id)
    }

    Client.post(client, url, body)
  end

  @doc """
  Gets reconciliation details for an event.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID

  ## Returns

    * `{:ok, details}` - Reconciliation details
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, details} = TinkEx.FinancialCalendar.get_reconciliation_details(
        client,
        "event_abc123"
      )
  """
  @spec get_reconciliation_details(Client.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_reconciliation_details(%Client{} = client, event_id)
      when is_binary(event_id) do
    url =
      "/finance-management/v1/financial-calendar-events/#{event_id}/reconciliations/details"

    Client.get(client, url)
  end

  @doc """
  Gets reconciliation suggestions for an event.

  Returns AI-powered suggestions for matching transactions.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID

  ## Returns

    * `{:ok, suggestions}` - List of suggested transactions
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, suggestions} = TinkEx.FinancialCalendar.get_reconciliation_suggestions(
        client,
        "event_abc123"
      )
      #=> {:ok, %{
      #     "suggestions" => [
      #       %{
      #         "transactionId" => "txn_1",
      #         "description" => "Electricity Company",
      #         "amount" => 125.00,
      #         "date" => "2024-02-14",
      #         "confidence" => "HIGH"
      #       },
      #       ...
      #     ]
      #   }}
  """
  @spec get_reconciliation_suggestions(Client.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_reconciliation_suggestions(%Client{} = client, event_id)
      when is_binary(event_id) do
    url =
      "/finance-management/v1/financial-calendar-events/#{event_id}/reconciliations/suggestions"

    Client.get(client, url)
  end

  @doc """
  Deletes a reconciliation.

  ## Parameters

    * `client` - TinkEx client with user bearer token
    * `event_id` - Calendar event ID
    * `transaction_id` - Transaction ID to unlink

  ## Returns

    * `:ok` - Reconciliation deleted successfully
    * `{:error, error}` - If the request fails

  ## Examples

      :ok = TinkEx.FinancialCalendar.delete_reconciliation(
        client,
        "event_abc123",
        "txn_xyz"
      )
  """
  @spec delete_reconciliation(Client.t(), String.t(), String.t()) ::
          :ok | {:error, Error.t()}
  def delete_reconciliation(%Client{} = client, event_id, transaction_id)
      when is_binary(event_id) and is_binary(transaction_id) do
    url =
      "/finance-management/v1/financial-calendar-events/#{event_id}/reconciliations/#{transaction_id}"

    case Client.delete(client, url) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp build_update_body(updates) do
    %{}
    |> maybe_add_field("title", updates[:title])
    |> maybe_add_field("description", updates[:description])
    |> maybe_add_field("eventAmount", updates[:event_amount])
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: params ++ [{key, value}]
end
