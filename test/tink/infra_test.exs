defmodule Tink.WebhooksTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2" do
    client = test_client()
    expect_http(:post, "/events/v2/webhook-endpoints", %{"id" => "wh-001"})
    assert {:ok, %{"id" => "wh-001"}} = Tink.Webhooks.create(client, %{url: "https://app.com/hook"})
  end

  test "list/1" do
    client = test_client()
    expect_http(:get, "/events/v2/webhook-endpoints", %{"webhookEndpoints" => []})
    assert {:ok, _} = Tink.Webhooks.list(client)
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/events/v2/webhook-endpoints/wh-001", %{"id" => "wh-001"})
    assert {:ok, _} = Tink.Webhooks.get(client, "wh-001")
  end

  test "update/3" do
    client = test_client()
    expect_http(:put, "/events/v2/webhook-endpoints/wh-001", %{"id" => "wh-001"})
    assert {:ok, _} = Tink.Webhooks.update(client, "wh-001", %{url: "https://app.com/new"})
  end

  test "delete/2 returns :ok" do
    client = test_client()
    expect_delete("/events/v2/webhook-endpoints/wh-001")
    assert :ok = Tink.Webhooks.delete(client, "wh-001")
  end
end

defmodule Tink.WebhookVerifierTest do
  use ExUnit.Case, async: true

  @secret "test_webhook_secret_32chars_long!"
  @body ~s({"event":"account.updated","content":{"id":"acc-001"}})

  defp sign(body, secret \\ @secret) do
    :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
  end

  test "verify/3 accepts correct HMAC signature" do
    assert :ok = Tink.WebhookVerifier.verify(@body, sign(@body), @secret)
  end

  test "verify/3 rejects wrong signature" do
    assert {:error, _} = Tink.WebhookVerifier.verify(@body, "badhex0000", @secret)
  end

  test "verify/3 rejects empty signature" do
    assert {:error, _} = Tink.WebhookVerifier.verify(@body, "", @secret)
  end

  test "verify/3 rejects a signature shorter than expected (no crash)" do
    short_sig = String.slice(sign(@body), 0, 10)
    assert {:error, _} = Tink.WebhookVerifier.verify(@body, short_sig, @secret)
  end

  test "verify/3 rejects a signature longer than expected (no crash)" do
    long_sig = sign(@body) <> "deadbeef"
    assert {:error, _} = Tink.WebhookVerifier.verify(@body, long_sig, @secret)
  end

  test "verify/3 rejects a same-length signature with wrong content" do
    correct = sign(@body)
    # Flip the last hex character — same length, different content.
    tampered =
      String.slice(correct, 0..-2//1) <> if(String.last(correct) == "a", do: "b", else: "a")

    assert {:error, _} = Tink.WebhookVerifier.verify(@body, tampered, @secret)
  end

  test "verify_with_config/2 uses configured webhook_secret" do
    sig = sign(@body)
    assert :ok = Tink.WebhookVerifier.verify_with_config(@body, sig)
  end

  test "verify_with_config/2 returns error when no secret configured" do
    original = Application.get_env(:tink, :webhook_secret)
    Application.put_env(:tink, :webhook_secret, nil)
    assert {:error, msg} = Tink.WebhookVerifier.verify_with_config(@body, sign(@body))
    assert String.contains?(msg, "No webhook secret")
    Application.put_env(:tink, :webhook_secret, original)
  end
end

defmodule Tink.WebhookHandlerTest do
  use ExUnit.Case, async: false

  setup do
    Tink.WebhookHandler.clear_handlers("account.updated")
    Tink.WebhookHandler.clear_handlers("transaction.created")
    Tink.WebhookHandler.clear_handlers("consent.revoked")
    :ok
  end

  test "handle/2 registers handler and dispatch/1 invokes it" do
    test_pid = self()

    Tink.WebhookHandler.handle("account.updated", fn event ->
      send(test_pid, {:received, event["content"]["id"]})
    end)

    Tink.WebhookHandler.dispatch(%{
      "event" => "account.updated",
      "content" => %{"id" => "acc-001"}
    })

    assert_receive {:received, "acc-001"}
  end

  test "multiple handlers for same event are all called" do
    test_pid = self()
    Tink.WebhookHandler.handle("account.updated", fn _ -> send(test_pid, :handler_a) end)
    Tink.WebhookHandler.handle("account.updated", fn _ -> send(test_pid, :handler_b) end)

    Tink.WebhookHandler.dispatch(%{"event" => "account.updated", "content" => %{}})

    assert_receive :handler_a
    assert_receive :handler_b
  end

  test "dispatch returns :ok for unregistered events" do
    assert :ok = Tink.WebhookHandler.dispatch(%{"event" => "unknown.event"})
  end

  test "dispatch returns :ok for maps without event key" do
    assert :ok = Tink.WebhookHandler.dispatch(%{"foo" => "bar"})
  end

  test "exceptions in handlers do not crash dispatch" do
    Tink.WebhookHandler.handle("transaction.created", fn _event ->
      raise "intentional crash in handler"
    end)

    assert :ok = Tink.WebhookHandler.dispatch(%{"event" => "transaction.created", "content" => %{}})
  end

  test "get_handlers/1 returns registered handlers" do
    fun = fn _ -> :ok end
    Tink.WebhookHandler.handle("consent.revoked", fun)
    handlers = Tink.WebhookHandler.get_handlers("consent.revoked")
    assert length(handlers) == 1
  end

  test "clear_handlers/1 removes all handlers for event" do
    Tink.WebhookHandler.handle("consent.revoked", fn _ -> :ok end)
    Tink.WebhookHandler.clear_handlers("consent.revoked")
    assert Tink.WebhookHandler.get_handlers("consent.revoked") == []
  end

  test "known_events/0 includes all expected events" do
    events = Tink.WebhookHandler.known_events()
    assert "account.updated" in events
    assert "payment.updated" in events
    assert "consent.revoked" in events
    assert length(events) >= 10
  end
end

defmodule Tink.LinkTest do
  use ExUnit.Case, async: true

  test "build_url/2 for :transactions" do
    url =
      Tink.Link.build_url(:transactions, %{
        client_id: "cid",
        redirect_uri: "https://app.com/cb",
        market: "GB",
        locale: "en_US"
      })

    assert String.starts_with?(url, "https://link.tink.com/1.0/transactions/connect-accounts")
    assert String.contains?(url, "client_id=cid")
    assert String.contains?(url, "market=GB")
  end

  test "build_url/2 for :payment" do
    url = Tink.Link.build_url(:payment, %{client_id: "cid", market: "SE"})
    assert String.contains?(url, "/1.0/pay")
    assert String.contains?(url, "market=SE")
  end

  test "build_url/2 for :account_check" do
    url = Tink.Link.build_url(:account_check, %{client_id: "cid"})
    assert String.contains?(url, "/1.0/account-check")
  end

  test "build_url/2 for :sweeping_vrp" do
    url = Tink.Link.build_url(:sweeping_vrp, %{client_id: "cid"})
    assert String.contains?(url, "/payments/sweeping-vrp/mandate")
  end

  test "build_session_url/3 appends session_id" do
    url = Tink.Link.build_session_url(:transactions, "sess-abc", %{client_id: "cid"})
    assert String.contains?(url, "session_id=sess-abc")
    assert String.contains?(url, "client_id=cid")
  end

  test "nil params are filtered out" do
    url = Tink.Link.build_url(:transactions, %{client_id: "cid", locale: nil})
    refute String.contains?(url, "locale")
  end

  test "keyword list params are accepted" do
    url = Tink.Link.build_url(:transactions, client_id: "cid", market: "GB")
    assert String.contains?(url, "client_id=cid")
    assert String.contains?(url, "market=GB")
  end

  test "supported_flows/0 returns all flow atoms" do
    flows = Tink.Link.supported_flows()
    assert :transactions in flows
    assert :payment in flows
    assert :account_check in flows
    assert :sweeping_vrp in flows
  end

  test "raises on unknown flow" do
    assert_raise KeyError, fn ->
      Tink.Link.build_url(:unknown_flow, %{})
    end
  end
end

defmodule Tink.ConnectorTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "upsert_accounts/3 posts to v1 endpoint" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/connector/users/user-123/accounts")
      body = Jason.decode!(body_str)
      assert length(body["accounts"]) == 1
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    assert {:ok, _} = Tink.Connector.upsert_accounts(client, "user-123", [account_fixture()])
  end

  test "upsert_transactions/3" do
    client = test_client()
    expect_http(:post, "/connector/users/user-123/transactions", %{})

    assert {:ok, _} =
             Tink.Connector.upsert_transactions(client, "user-123", [transaction_fixture()])
  end

  test "batch_delete_transactions/2" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/data/v2/connector/transactions:batchDelete")
      body = Jason.decode!(body_str)
      assert body["externalIds"] == ["tx-001", "tx-002"]
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    assert {:ok, _} = Tink.Connector.batch_delete_transactions(client, ["tx-001", "tx-002"])
  end

  test "batch_update_transactions/2" do
    client = test_client()
    expect_http(:post, "/data/v2/connector/transactions:batchUpdate", %{})
    assert {:ok, _} = Tink.Connector.batch_update_transactions(client, [transaction_fixture()])
  end

  test "upsert_accounts_v2/2" do
    client = test_client()
    expect_http(:post, "/data/v2/connector/accounts", %{})
    assert {:ok, _} = Tink.Connector.upsert_accounts_v2(client, [account_fixture()])
  end

  test "delete_accounts/2" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/data/v2/connector/accounts:delete")
      body = Jason.decode!(body_str)
      assert body["externalIds"] == ["acc-001"]
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    assert {:ok, _} = Tink.Connector.delete_accounts(client, ["acc-001"])
  end

  test "get_operation/2" do
    client = test_client()
    expect_http(:get, "/data/v2/connector/operations/op-001", %{"status" => "COMPLETED"})
    assert {:ok, %{"status" => "COMPLETED"}} = Tink.Connector.get_operation(client, "op-001")
  end

  test "poll_operation/3 returns on COMPLETED" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
      {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"status" => "COMPLETED"})}}
    end)

    assert {:ok, _} =
             Tink.Connector.poll_operation(client, "op-001", timeout_ms: 1_000, interval_ms: 10)
  end

  test "delete_user/2 returns :ok" do
    client = test_client()
    expect_delete("/connector/users/user-123")
    assert :ok = Tink.Connector.delete_user(client, "user-123")
  end
end

defmodule Tink.ConsentsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2" do
    client = test_client()
    expect_http(:post, "/connectivity/v2/consents", %{"id" => "con-001"})
    assert {:ok, %{"id" => "con-001"}} = Tink.Consents.create(client, %{})
  end

  test "list/2" do
    client = test_client()
    expect_http(:get, "/connectivity/v2/consents", %{"consents" => []})
    assert {:ok, _} = Tink.Consents.list(client)
  end

  test "get/2" do
    client = test_client()

    expect_http(:get, "/connectivity/v2/consents/con-001", %{
      "id" => "con-001",
      "status" => "ACTIVE"
    })

    assert {:ok, %{"status" => "ACTIVE"}} = Tink.Consents.get(client, "con-001")
  end

  test "revoke/2" do
    client = test_client()
    expect_http(:post, "/connectivity/v2/consents/con-001:revoke", %{})
    assert {:ok, _} = Tink.Consents.revoke(client, "con-001")
  end

  test "list_authorizations/2" do
    client = test_client()
    expect_http(:get, "/connectivity/v2/consents/con-001/authorizations", %{"authorizations" => []})
    assert {:ok, _} = Tink.Consents.list_authorizations(client, "con-001")
  end

  test "get_authorization/3" do
    client = test_client()

    expect_http(:get, "/connectivity/v2/consents/con-001/authorizations/auth-001", %{
      "id" => "auth-001"
    })

    assert {:ok, _} = Tink.Consents.get_authorization(client, "con-001", "auth-001")
  end

  test "relay_authorization_callback/2" do
    client = test_client()
    expect_http(:post, "/connectivity/v2/authorizations:relay-callback", %{})
    assert {:ok, _} = Tink.Consents.relay_authorization_callback(client, %{})
  end

  test "get_template/2" do
    client = test_client()
    expect_http(:get, "/connectivity/v2/consent-templates/uk-monzo", %{"fields" => []})
    assert {:ok, _} = Tink.Consents.get_template(client, "uk-monzo")
  end

  test "ProviderConsents.list/1" do
    client = test_client()
    expect_http(:get, "/api/v1/provider-consents", %{"consents" => []})
    assert {:ok, _} = Tink.ProviderConsents.list(client)
  end

  test "ProviderConsents.extend/2" do
    client = test_client()
    expect_http(:post, "/api/v1/provider-consents:extend", %{})
    assert {:ok, _} = Tink.ProviderConsents.extend(client, %{})
  end
end

defmodule Tink.MiscTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "ReportJobs.get/2" do
    client = test_client()

    expect_http(:get, "/api/v1/reports-generation-jobs/job-001", %{
      "id" => "job-001",
      "status" => "READY"
    })

    assert {:ok, _} = Tink.ReportJobs.get(client, "job-001")
  end

  test "ReportJobs.poll_until_complete/3" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
      {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"status" => "READY"})}}
    end)

    assert {:ok, _} =
             Tink.ReportJobs.poll_until_complete(client, "job-001",
               timeout_ms: 1_000,
               interval_ms: 10
             )
  end

  test "TransactionReports.get/2" do
    client = test_client()
    expect_http(:get, "/data/v2/transaction-reports/rpt-001", %{"id" => "rpt-001"})
    assert {:ok, _} = Tink.TransactionReports.get(client, "rpt-001")
  end

  test "Merchants.create/2" do
    client = test_client()
    expect_http(:post, "/partner-integration/v1/merchants", %{"id" => "m-001"})
    assert {:ok, _} = Tink.Merchants.create(client, %{name: "Acme"})
  end

  test "Merchants.list/2" do
    client = test_client()
    expect_http(:get, "/partner-integration/v1/merchants", %{"merchants" => []})
    assert {:ok, _} = Tink.Merchants.list(client)
  end

  test "Merchants.get/2" do
    client = test_client()
    expect_http(:get, "/partner-integration/v1/merchants/m-001", %{"id" => "m-001"})
    assert {:ok, _} = Tink.Merchants.get(client, "m-001")
  end
end
