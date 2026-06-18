defmodule Tink.AccountCheckTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2" do
    client = test_client()
    expect_http(:post, "/api/v1/account-verification-reports", %{"id" => "rpt-001"})
    assert {:ok, %{"id" => "rpt-001"}} = Tink.AccountCheck.create(client, %{})
  end

  test "get/2" do
    client = test_client()

    expect_http(:get, "/api/v1/account-verification-reports/rpt-001", %{
      "id" => "rpt-001",
      "status" => "DONE"
    })

    assert {:ok, _} = Tink.AccountCheck.get(client, "rpt-001")
  end

  test "get_pdf/2 sends accept: application/pdf header" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :get, url, headers, _b, _o ->
      assert String.contains?(url, "/api/v1/account-verification-reports/rpt-001/pdf")
      assert Enum.any?(headers, fn {k, v} -> k == "accept" and String.contains?(v, "pdf") end)
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    assert {:ok, _} = Tink.AccountCheck.get_pdf(client, "rpt-001")
  end
end

defmodule Tink.IncomeCheckTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2" do
    client = test_client()
    expect_http(:post, "/v2/income-checks", %{"id" => "ic-001"})
    assert {:ok, _} = Tink.IncomeCheck.create(client, %{})
  end

  test "list/2" do
    client = test_client()
    expect_http(:get, "/v2/income-checks", %{"incomeChecks" => []})
    assert {:ok, _} = Tink.IncomeCheck.list(client)
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/v2/income-checks/ic-001", %{"id" => "ic-001"})
    assert {:ok, _} = Tink.IncomeCheck.get(client, "ic-001")
  end

  test "generate_pdf/2" do
    client = test_client()
    expect_http(:post, "/v2/income-checks/ic-001:generate-pdf", %{"jobId" => "job-001"})
    assert {:ok, _} = Tink.IncomeCheck.generate_pdf(client, "ic-001")
  end

  test "delete/2 returns :ok" do
    client = test_client()
    expect_delete("/v2/income-checks/ic-001")
    assert :ok = Tink.IncomeCheck.delete(client, "ic-001")
  end
end

defmodule Tink.ExpenseCheckTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2" do
    client = test_client()
    expect_http(:post, "/risk/v1/expense-checks", %{"id" => "ec-001"})
    assert {:ok, _} = Tink.ExpenseCheck.create(client, %{})
  end

  test "list/2" do
    client = test_client()
    expect_http(:get, "/risk/v1/expense-checks", %{"expenseChecks" => []})
    assert {:ok, _} = Tink.ExpenseCheck.list(client)
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/risk/v1/expense-checks/ec-001", %{"id" => "ec-001"})
    assert {:ok, _} = Tink.ExpenseCheck.get(client, "ec-001")
  end

  test "delete/2 returns :ok" do
    client = test_client()
    expect_delete("/risk/v1/expense-checks/ec-001")
    assert :ok = Tink.ExpenseCheck.delete(client, "ec-001")
  end
end

defmodule Tink.RiskInsightsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2" do
    client = test_client()
    expect_http(:post, "/risk/v1/risk-insights", %{"id" => "ri-001"})
    assert {:ok, _} = Tink.RiskInsights.create(client, %{})
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/risk/v1/risk-insights/ri-001", %{"id" => "ri-001", "status" => "READY"})
    assert {:ok, _} = Tink.RiskInsights.get(client, "ri-001")
  end

  test "delete/2 returns :ok" do
    client = test_client()
    expect_delete("/risk/v1/risk-insights/ri-001")
    assert :ok = Tink.RiskInsights.delete(client, "ri-001")
  end
end

defmodule Tink.BalanceCheckTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "trigger_refresh/2" do
    client = test_client()
    expect_http(:post, "/api/v1/balance-refresh", %{"refreshId" => "ref-001"})
    assert {:ok, %{"refreshId" => "ref-001"}} = Tink.BalanceCheck.trigger_refresh(client)
  end

  test "get_refresh_status/2" do
    client = test_client()
    expect_http(:get, "/api/v1/balance-refresh/ref-001", %{"status" => "DONE"})
    assert {:ok, %{"status" => "DONE"}} = Tink.BalanceCheck.get_refresh_status(client, "ref-001")
  end

  test "poll_until_complete/3 returns on DONE" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
      {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"status" => "DONE"})}}
    end)

    assert {:ok, %{"status" => "DONE"}} =
             Tink.BalanceCheck.poll_until_complete(client, "ref-001",
               timeout_ms: 1_000,
               interval_ms: 10
             )
  end

  test "poll_until_complete/3 returns :timeout" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
      {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"status" => "IN_PROGRESS"})}}
    end)

    assert {:error, :timeout} =
             Tink.BalanceCheck.poll_until_complete(client, "ref-001",
               timeout_ms: 60,
               interval_ms: 20
             )
  end
end
