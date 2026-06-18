defmodule Tink.IntegrationTest do
  @moduledoc """
  End-to-end integration tests that exercise the full SDK pipeline:
  Auth → Client → API Module → Response.

  These tests use the Mox HTTP adapter (configured in test.exs) but
  exercise all layers: auth flow, token building, request routing,
  header injection, response parsing, error handling, and pagination.
  """

  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers

  setup :verify_on_exit!

  # ── Full auth + data flow ─────────────────────────────────────────────────────

  describe "complete auth → data flow" do
    test "client credentials → create user → get accounts" do
      # Step 1: get app client
      expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
        assert String.contains?(url, "/api/v1/oauth/token")
        assert String.contains?(body_str, "grant_type=client_credentials")

        {:ok,
         %{
           status: 200,
           headers: [],
           body: Jason.encode!(token_response(scope: "user:create accounts:read"))
         }}
      end)

      {:ok, app_client} = Tink.Auth.client_credentials(scope: "user:create accounts:read")
      assert app_client.access_token == "fake_access_token_xyz"
      assert Tink.AuthToken.has_scope?(app_client, "user:create")
      assert Tink.AuthToken.has_scope?(app_client, "accounts:read")
      refute Tink.AuthToken.expired?(app_client)

      # Step 2: create a user
      expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
        assert String.contains?(url, "/api/v1/user/create")
        body = Jason.decode!(body_str)
        assert body["externalUserId"] == "my-user-001"
        assert body["market"] == "GB"

        {:ok,
         %{status: 200, headers: [], body: Jason.encode!(%{"user" => %{"id" => "tink-user-001"}})}}
      end)

      {:ok, %{"user" => %{"id" => tink_user_id}}} =
        Tink.Users.create_user(app_client, %{external_user_id: "my-user-001", market: "GB"})

      assert tink_user_id == "tink-user-001"

      # Step 3: create authorization grant
      expect(Tink.HTTP.Mock, :request, fn :post, url, headers, body_str, _o ->
        assert String.contains?(url, "/api/v1/oauth/authorization-grant")
        assert {"content-type", "application/x-www-form-urlencoded"} in headers
        body = URI.decode_query(body_str)
        assert body["user_id"] == "tink-user-001"
        {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"code" => "auth-grant-code-abc"})}}
      end)

      {:ok, %{"code" => grant_code}} =
        Tink.Auth.create_authorization(app_client,
          user_id: tink_user_id,
          scope: "accounts:read,transactions:read,balances:read"
        )

      # Step 4: exchange grant code for user token
      expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
        assert String.contains?(url, "/api/v1/oauth/token")
        assert String.contains?(body_str, "grant_type=authorization_code")
        assert String.contains?(body_str, "code=auth-grant-code-abc")

        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(token_response(scope: "accounts:read,transactions:read,balances:read"))
         }}
      end)

      {:ok, user_client} = Tink.Auth.user_client(grant_code)

      # Step 5: fetch accounts with user token
      expect(Tink.HTTP.Mock, :request, fn :get, url, headers, _b, _o ->
        assert String.contains?(url, "/data/v2/accounts")
        auth = Enum.find_value(headers, fn {k, v} -> if k == "authorization", do: v end)
        assert auth == "Bearer fake_access_token_xyz"

        {:ok,
         %{status: 200, headers: [], body: Jason.encode!(%{"accounts" => [account_fixture()]})}}
      end)

      {:ok, %{"accounts" => accounts}} = Tink.Accounts.list(user_client)
      assert length(accounts) == 1
      assert hd(accounts)["id"] == "acc-001"
    end
  end

  # ── Error propagation ─────────────────────────────────────────────────────────

  describe "error propagation" do
    test "401 from token endpoint bubbles as Tink.Error" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _b, _o ->
        {:ok,
         %{
           status: 401,
           headers: [],
           body:
             Jason.encode!(%{
               "errorCode" => "AUTHENTICATION_ERROR",
               "errorMessage" => "Invalid client secret"
             })
         }}
      end)

      assert {:error, %Tink.Error{status: 401, code: "AUTHENTICATION_ERROR"}} =
               Tink.Auth.client_credentials(scope: "accounts:read")
    end

    test "403 from data endpoint bubbles as Tink.Error with scope info" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        {:ok,
         %{
           status: 403,
           headers: [{"x-tink-request-id", "req-xyz-789"}],
           body:
             Jason.encode!(%{
               "errorCode" => "FORBIDDEN",
               "errorMessage" => "Missing scope: accounts:read"
             })
         }}
      end)

      assert {:error, %Tink.Error{status: 403, code: "FORBIDDEN", request_id: "req-xyz-789"}} =
               Tink.Accounts.list(client)
    end

    test "network failure returns NETWORK_ERROR" do
      client = test_client()

      stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        {:error, :econnrefused}
      end)

      assert {:error, %Tink.Error{status: nil, code: "NETWORK_ERROR"}} = Tink.Accounts.list(client)
    end

    test "malformed JSON response returns DECODE_ERROR" do
      client = test_client()

      stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        {:ok, %{status: 200, headers: [], body: "not-json{{{"}}
      end)

      assert {:error, %Tink.Error{code: "DECODE_ERROR"}} = Tink.Accounts.list(client)
    end
  end

  # ── Pagination ────────────────────────────────────────────────────────────────

  describe "pagination" do
    test "stream/2 fetches all pages lazily" do
      client = test_client()
      call_count = :counters.new(1, [:atomics])

      stub(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
        :counters.add(call_count, 1, 1)
        n = :counters.get(call_count, 1)

        page =
          cond do
            String.contains?(url, "pageToken=p2") ->
              %{
                "transactions" => Enum.map(3..4, &transaction_fixture("tx-00#{&1}")),
                "nextPageToken" => "p3"
              }

            String.contains?(url, "pageToken=p3") ->
              %{"transactions" => [transaction_fixture("tx-005")], "nextPageToken" => nil}

            n == 1 ->
              %{
                "transactions" => Enum.map(1..2, &transaction_fixture("tx-00#{&1}")),
                "nextPageToken" => "p2"
              }

            true ->
              %{"transactions" => [], "nextPageToken" => nil}
          end

        {:ok, %{status: 200, headers: [], body: Jason.encode!(page)}}
      end)

      result = Tink.Transactions.stream(client) |> Enum.to_list()
      assert length(result) == 5
      assert Enum.map(result, & &1["id"]) == ~w[tx-001 tx-002 tx-003 tx-004 tx-005]
    end

    test "Paginator.stream/2 stops early on Enum.take" do
      client = test_client()
      call_count = :counters.new(1, [:atomics])

      stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        :counters.add(call_count, 1, 1)

        page = %{
          "transactions" => Enum.map(1..10, &transaction_fixture("tx-#{&1}")),
          "nextPageToken" => "always-has-more"
        }

        {:ok, %{status: 200, headers: [], body: Jason.encode!(page)}}
      end)

      result = Tink.Transactions.stream(client) |> Enum.take(3)
      assert length(result) == 3
      # Should have fetched only 1 page to satisfy the take(3)
      assert :counters.get(call_count, 1) == 1
    end
  end

  # ── Webhook pipeline ──────────────────────────────────────────────────────────

  describe "webhook pipeline" do
    setup do
      Tink.WebhookHandler.clear_handlers("account.updated")
      Tink.WebhookHandler.clear_handlers("transaction.created")
      :ok
    end

    test "verify signature → dispatch → handler receives event" do
      secret = "test_webhook_secret_32chars_long!"

      payload = %{
        "event" => "account.updated",
        "content" => %{"id" => "acc-001", "type" => "CHECKING"}
      }

      body = Jason.encode!(payload)
      sig = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

      test_pid = self()

      Tink.WebhookHandler.handle("account.updated", fn event ->
        send(test_pid, {:webhook, event["content"]["id"]})
      end)

      assert :ok = Tink.WebhookVerifier.verify_with_config(body, sig)

      {:ok, event} = Jason.decode(body)
      Tink.WebhookHandler.dispatch(event)

      assert_receive {:webhook, "acc-001"}, 500
    end

    test "tampered signature is rejected before dispatch" do
      body = ~s({"event":"account.updated","content":{}})
      bad_sig = "0000000000000000000000000000000000000000000000000000000000000000"

      assert {:error, "Invalid webhook signature"} =
               Tink.WebhookVerifier.verify_with_config(body, bad_sig)
    end
  end

  # ── AuthToken integration ─────────────────────────────────────────────────────

  describe "AuthToken integration with live client" do
    test "client built from auth has correct scope metadata" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _b, _o ->
        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(
               token_response(
                 scope: "accounts:read transactions:read balances:read",
                 expires_in: 3600
               )
             )
         }}
      end)

      {:ok, client} =
        Tink.Auth.client_credentials(scope: "accounts:read transactions:read balances:read")

      assert Tink.AuthToken.has_scope?(client, "accounts:read")
      assert Tink.AuthToken.has_scope?(client, "transactions:read")
      refute Tink.AuthToken.has_scope?(client, "payment:write")
      refute Tink.AuthToken.expired?(client)
      refute Tink.AuthToken.should_refresh?(client)

      missing = Tink.AuthToken.missing_scopes(client, ["accounts:read", "payment:write"])
      assert missing == ["payment:write"]

      summary = Tink.AuthToken.summary(client)
      assert summary.scope_count == 3
      refute summary.expired
    end
  end

  # ── Payment polling ───────────────────────────────────────────────────────────

  describe "payment polling" do
    test "polls until SUCCESSFUL" do
      client = test_client()
      call_count = :counters.new(1, [:atomics])

      stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        :counters.add(call_count, 1, 1)
        n = :counters.get(call_count, 1)
        status = if n >= 3, do: "SUCCESSFUL", else: "PENDING"

        {:ok,
         %{status: 200, headers: [], body: Jason.encode!(%{"id" => "pay-001", "status" => status})}}
      end)

      assert {:ok, %{"status" => "SUCCESSFUL"}} =
               Tink.Payments.poll_until_terminal(client, "pay-001",
                 timeout_ms: 5_000,
                 interval_ms: 10
               )

      assert :counters.get(call_count, 1) == 3
    end

    test "returns :timeout when payment never completes" do
      client = test_client()

      stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"status" => "PENDING"})}}
      end)

      assert {:error, :timeout} =
               Tink.Payments.poll_until_terminal(client, "pay-001", timeout_ms: 80, interval_ms: 20)
    end
  end

  # ── Connector + enrichment pipeline ──────────────────────────────────────────

  describe "connector ingestion + enrichment" do
    test "ingest accounts, ingest transactions, enrich" do
      client = test_client()

      # Ingest accounts
      expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
        assert String.contains?(url, "/connector/users/ext-user-001/accounts")
        body = Jason.decode!(body_str)
        assert length(body["accounts"]) == 1
        {:ok, %{status: 200, headers: [], body: ~s({})}}
      end)

      {:ok, _} =
        Tink.Connector.upsert_accounts(client, "ext-user-001", [
          %{"externalId" => "acc-ext-001", "name" => "Current", "type" => "CHECKING"}
        ])

      # Ingest transactions
      expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
        assert String.contains?(url, "/connector/users/ext-user-001/transactions")
        body = Jason.decode!(body_str)
        assert length(body["transactions"]) == 2
        {:ok, %{status: 200, headers: [], body: ~s({"operationId":"op-001"})}}
      end)

      {:ok, %{"operationId" => op_id}} =
        Tink.Connector.upsert_transactions(client, "ext-user-001", [
          %{
            "externalId" => "tx-ext-001",
            "accountExternalId" => "acc-ext-001",
            "description" => "Spotify",
            "amount" => %{"currencyCode" => "GBP", "value" => -9.99}
          },
          %{
            "externalId" => "tx-ext-002",
            "accountExternalId" => "acc-ext-001",
            "description" => "Netflix",
            "amount" => %{"currencyCode" => "GBP", "value" => -15.99}
          }
        ])

      assert op_id == "op-001"

      # Poll operation to completion
      expect(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
        assert String.contains?(url, "/data/v2/connector/operations/op-001")
        {:ok, %{status: 200, headers: [], body: ~s({"status":"COMPLETED"})}}
      end)

      {:ok, %{"status" => "COMPLETED"}} =
        Tink.Connector.poll_operation(client, op_id, timeout_ms: 5_000, interval_ms: 10)

      # On-demand enrichment
      expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
        assert String.contains?(url, "/enrichment/v1/transactions/on-demand")
        body = Jason.decode!(body_str)
        assert length(body["transactions"]) == 1

        {:ok,
         %{
           status: 200,
           headers: [],
           body: ~s({"transactions":[{"category":{"primaryName":"Entertainment"}}]})
         }}
      end)

      {:ok, %{"transactions" => [enriched]}} =
        Tink.Enrichment.OnDemand.enrich(client, [
          %{
            "description" => "Spotify",
            "amount" => %{"value" => %{"unscaledValue" => 999, "scale" => 2}}
          }
        ])

      assert get_in(enriched, ["category", "primaryName"]) == "Entertainment"
    end
  end

  # ── Header assertions ─────────────────────────────────────────────────────────

  describe "request headers" do
    test "all requests include Authorization, Accept, User-Agent headers" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :get, _url, headers, _b, _o ->
        header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
        assert Map.has_key?(header_map, "authorization")
        assert String.starts_with?(header_map["authorization"], "Bearer ")
        assert header_map["accept"] == "application/json"
        assert String.contains?(header_map["user-agent"], "tink-elixir")
        {:ok, %{status: 200, headers: [], body: ~s({})}}
      end)

      Tink.Client.get(client, "/api/v1/any")
    end

    test "POST requests include content-type application/json" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, headers, _b, _o ->
        header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
        assert String.contains?(header_map["content-type"], "application/json")
        {:ok, %{status: 201, headers: [], body: ~s({})}}
      end)

      Tink.Client.post(client, "/api/v1/any", %{})
    end

    test "OAuth token requests use form encoding" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, headers, body, _o ->
        header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
        assert String.contains?(header_map["content-type"], "application/x-www-form-urlencoded")
        assert String.contains?(body, "grant_type=client_credentials")
        refute String.starts_with?(body, "{")
        {:ok, %{status: 200, headers: [], body: Jason.encode!(token_response())}}
      end)

      Tink.Auth.client_credentials(scope: "accounts:read")
    end
  end
end
