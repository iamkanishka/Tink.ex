defmodule Tink.PaymentsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2 posts payment request" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/payments/requests")
      body = Jason.decode!(body_str)
      assert body["market"] == "GB"
      {:ok, %{status: 200, headers: [], body: Jason.encode!(payment_fixture())}}
    end)

    assert {:ok, %{"id" => "pay-001"}} = Tink.Payments.create(client, %{"market" => "GB"})
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/api/v1/payments/requests/pay-001", payment_fixture())
    assert {:ok, %{"status" => "PENDING"}} = Tink.Payments.get(client, "pay-001")
  end

  test "get_transfers/2" do
    client = test_client()
    expect_http(:get, "/api/v1/payments/requests/pay-001/transfers", %{"transfers" => []})
    assert {:ok, _} = Tink.Payments.get_transfers(client, "pay-001")
  end

  test "cancel/2" do
    client = test_client()
    expect_http(:post, "/api/v1/payments/pay-001/cancellation", %{})
    assert {:ok, _} = Tink.Payments.cancel(client, "pay-001")
  end

  test "get_conditions/2" do
    client = test_client()
    expect_http(:get, "/api/v1/payments/providers/uk-monzo/payment-conditions", %{})
    assert {:ok, _} = Tink.Payments.get_conditions(client, "uk-monzo")
  end

  test "create_settlement_payment/2" do
    client = test_client()
    expect_http(:post, "/payment/v1/settlement-account-payment-requests", %{"id" => "sp-001"})
    assert {:ok, _} = Tink.Payments.create_settlement_payment(client, %{})
  end

  test "poll_until_terminal/3 returns on SUCCESSFUL immediately" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
      {:ok,
       %{
         status: 200,
         headers: [],
         body: Jason.encode!(Map.put(payment_fixture(), "status", "SUCCESSFUL"))
       }}
    end)

    assert {:ok, %{"status" => "SUCCESSFUL"}} =
             Tink.Payments.poll_until_terminal(client, "pay-001",
               timeout_ms: 5_000,
               interval_ms: 10
             )
  end

  test "poll_until_terminal/3 returns error on FAILED" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
      {:ok,
       %{
         status: 200,
         headers: [],
         body: Jason.encode!(Map.put(payment_fixture(), "status", "FAILED"))
       }}
    end)

    assert {:error, %Tink.Error{status: 422}} =
             Tink.Payments.poll_until_terminal(client, "pay-001",
               timeout_ms: 5_000,
               interval_ms: 10
             )
  end

  test "poll_until_terminal/3 returns :timeout if never terminal" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
      {:ok, %{status: 200, headers: [], body: Jason.encode!(payment_fixture())}}
    end)

    assert {:error, :timeout} =
             Tink.Payments.poll_until_terminal(client, "pay-001", timeout_ms: 80, interval_ms: 20)
  end
end

defmodule Tink.MandatePaymentsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2 (v2)" do
    client = test_client()
    expect_http(:post, "/payment/v2/mandate-payments", %{"id" => "mp-001"})
    assert {:ok, _} = Tink.MandatePayments.create(client, %{})
  end

  test "get/2 (v2)" do
    client = test_client()

    expect_http(:get, "/payment/v2/mandate-payments/mp-001", %{
      "id" => "mp-001",
      "status" => "PENDING"
    })

    assert {:ok, _} = Tink.MandatePayments.get(client, "mp-001")
  end

  test "create_v1/2" do
    client = test_client()
    expect_http(:post, "/payment/v1/mandate-payments", %{"id" => "mp-v1"})
    assert {:ok, _} = Tink.MandatePayments.create_v1(client, %{})
  end

  test "get_v1/2" do
    client = test_client()
    expect_http(:get, "/payment/v1/mandate-payments/mp-v1", %{"id" => "mp-v1"})
    assert {:ok, _} = Tink.MandatePayments.get_v1(client, "mp-v1")
  end

  test "Mandates.get/2" do
    client = test_client()
    expect_http(:get, "/payment/v1/mandates/mand-001", %{"id" => "mand-001"})
    assert {:ok, _} = Tink.Mandates.get(client, "mand-001")
  end

  test "Mandates.revoke/2" do
    client = test_client()
    expect_http(:post, "/payment/v1/mandates/mand-001:revoke", %{})
    assert {:ok, _} = Tink.Mandates.revoke(client, "mand-001")
  end

  test "BulkPayments.create/2" do
    client = test_client()
    expect_http(:post, "/payment/v1/bulk-payments", %{"id" => "bp-001"})
    assert {:ok, _} = Tink.BulkPayments.create(client, %{})
  end

  test "BulkPayments.get/2" do
    client = test_client()
    expect_http(:get, "/payment/v1/bulk-payments/bp-001", %{"id" => "bp-001"})
    assert {:ok, _} = Tink.BulkPayments.get(client, "bp-001")
  end
end

defmodule Tink.SettlementAccountsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/2" do
    client = test_client()
    expect_http(:get, "/payment/v1/merchants/m-001/accounts", %{"accounts" => []})
    assert {:ok, _} = Tink.SettlementAccounts.list(client, "m-001")
  end

  test "get/3" do
    client = test_client()
    expect_http(:get, "/payment/v1/merchants/m-001/accounts/a-001", %{"id" => "a-001"})
    assert {:ok, _} = Tink.SettlementAccounts.get(client, "m-001", "a-001")
  end

  test "update/4" do
    client = test_client()
    expect_http(:put, "/payment/v1/merchants/m-001/accounts/a-001", %{})
    assert {:ok, _} = Tink.SettlementAccounts.update(client, "m-001", "a-001", %{})
  end

  test "create_refund/4" do
    client = test_client()
    expect_http(:post, "/payment/v1/merchants/m-001/accounts/a-001/refunds", %{"id" => "r-001"})
    assert {:ok, _} = Tink.SettlementAccounts.create_refund(client, "m-001", "a-001", %{amount: 50})
  end

  test "get_refund/4" do
    client = test_client()

    expect_http(:get, "/payment/v1/merchants/m-001/accounts/a-001/refunds/r-001", %{"id" => "r-001"})

    assert {:ok, _} = Tink.SettlementAccounts.get_refund(client, "m-001", "a-001", "r-001")
  end

  test "list_refunds/3" do
    client = test_client()
    expect_http(:get, "/payment/v1/merchants/m-001/accounts/a-001/refunds", %{"refunds" => []})
    assert {:ok, _} = Tink.SettlementAccounts.list_refunds(client, "m-001", "a-001")
  end

  test "create_withdrawal/4" do
    client = test_client()
    expect_http(:post, "/payment/v1/merchants/m-001/accounts/a-001/withdrawals", %{"id" => "w-001"})

    assert {:ok, _} =
             Tink.SettlementAccounts.create_withdrawal(client, "m-001", "a-001", %{amount: 100})
  end

  test "list_transactions/4" do
    client = test_client()

    expect_http(:get, "/payment/v1/merchants/m-001/accounts/a-001/transactions", %{
      "transactions" => []
    })

    assert {:ok, _} = Tink.SettlementAccounts.list_transactions(client, "m-001", "a-001")
  end

  test "get_transaction/4" do
    client = test_client()

    expect_http(:get, "/payment/v1/merchants/m-001/accounts/a-001/transactions/t-001", %{
      "id" => "t-001"
    })

    assert {:ok, _} = Tink.SettlementAccounts.get_transaction(client, "m-001", "a-001", "t-001")
  end
end
