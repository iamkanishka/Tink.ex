defmodule Tink.InvestmentsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1" do
    client = test_client()
    expect_http(:get, "/data/v2/investment-accounts", %{"investmentAccounts" => []})
    assert {:ok, _} = Tink.Investments.list(client)
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/data/v2/investment-accounts/inv-001", %{"id" => "inv-001"})
    assert {:ok, _} = Tink.Investments.get(client, "inv-001")
  end

  test "get_holdings/2" do
    client = test_client()
    expect_http(:get, "/data/v2/investment-accounts/inv-001/holdings", %{"holdings" => []})
    assert {:ok, _} = Tink.Investments.get_holdings(client, "inv-001")
  end

  test "list_transactions/3" do
    client = test_client()
    expect_http(:get, "/data/v2/investment-accounts/inv-001/transactions", %{"transactions" => []})
    assert {:ok, _} = Tink.Investments.list_transactions(client, "inv-001")
  end

  test "list_v1/1" do
    client = test_client()
    expect_http(:get, "/api/v1/investments", %{"accounts" => []})
    assert {:ok, _} = Tink.Investments.list_v1(client)
  end
end

defmodule Tink.LoansTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1 (v1)" do
    client = test_client()
    expect_http(:get, "/api/v1/loans", %{"loans" => []})
    assert {:ok, _} = Tink.Loans.list(client)
  end

  test "list_v2/2" do
    client = test_client()
    expect_http(:get, "/data/v2/loan-accounts", %{"loanAccounts" => []})
    assert {:ok, _} = Tink.Loans.list_v2(client)
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/data/v2/loan-accounts/loan-001", %{"id" => "loan-001"})
    assert {:ok, _} = Tink.Loans.get(client, "loan-001")
  end
end

defmodule Tink.IdentitiesTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1 (v1)" do
    client = test_client()
    expect_http(:get, "/api/v1/identities", %{"identities" => []})
    assert {:ok, _} = Tink.Identities.list(client)
  end

  test "list_v2/1" do
    client = test_client()
    expect_http(:get, "/data/v2/identities", %{"identities" => []})
    assert {:ok, _} = Tink.Identities.list_v2(client)
  end
end

defmodule Tink.StatisticsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "query/2 posts correct body" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/statistics/query")
      body = Jason.decode!(body_str)
      assert body["resolution"] == "MONTHLY"
      assert body["periodStart"] == "2024-01"
      assert body["periodEnd"] == "2024-12"
      {:ok, %{status: 200, headers: [], body: ~s({"statistics":[]})}}
    end)

    assert {:ok, _} =
             Tink.Statistics.query(client,
               resolution: "MONTHLY",
               period_start: "2024-01",
               period_end: "2024-12",
               statistic_types: ["EXPENSES_BY_CATEGORY"]
             )
  end

  test "query/2 omits nil fields" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
      body = Jason.decode!(body_str)
      refute Map.has_key?(body, "periodStart")
      refute Map.has_key?(body, "currency")
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    Tink.Statistics.query(client, resolution: "MONTHLY")
  end
end

defmodule Tink.FinancialCalendarTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list_periods/1" do
    client = test_client()
    expect_http(:get, "/api/v1/calendar/periods", %{"periods" => []})
    assert {:ok, _} = Tink.FinancialCalendar.list_periods(client)
  end

  test "get_period/2" do
    client = test_client()
    expect_http(:get, "/api/v1/calendar/periods/2024-01", %{"id" => "2024-01"})
    assert {:ok, _} = Tink.FinancialCalendar.get_period(client, "2024-01")
  end
end

defmodule Tink.SubscriptionsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1" do
    client = test_client()
    expect_http(:get, "/finance-management/v1/subscriptions", %{"subscriptions" => []})
    assert {:ok, _} = Tink.Subscriptions.list(client)
  end

  test "get_transactions/2" do
    client = test_client()

    expect_http(:get, "/finance-management/v1/subscriptions/sub-001/transactions", %{
      "transactions" => []
    })

    assert {:ok, _} = Tink.Subscriptions.get_transactions(client, "sub-001")
  end

  test "update/3" do
    client = test_client()
    expect_http(:put, "/finance-management/v1/subscriptions/sub-001", %{})
    assert {:ok, _} = Tink.Subscriptions.update(client, "sub-001", %{status: "KNOWN"})
  end
end

defmodule Tink.CostOfLivingTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1" do
    client = test_client()
    expect_http(:get, "/finance-management/v1/cost-of-living", %{"entries" => []})
    assert {:ok, _} = Tink.CostOfLiving.list(client)
  end

  test "get_transactions/2" do
    client = test_client()

    expect_http(:get, "/finance-management/v1/cost-of-living/col-001/transactions", %{
      "transactions" => []
    })

    assert {:ok, _} = Tink.CostOfLiving.get_transactions(client, "col-001")
  end

  test "update/3" do
    client = test_client()
    expect_http(:put, "/finance-management/v1/cost-of-living/col-001", %{})
    assert {:ok, _} = Tink.CostOfLiving.update(client, "col-001", %{status: "REVIEWED"})
  end
end

defmodule Tink.CashFlowTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "query/2 sends correct statistic_types" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/statistics/query")
      body = Jason.decode!(body_str)
      types = body["statisticTypes"]
      assert "EXPENSES_BY_CATEGORY" in types
      assert "INCOME_BY_CATEGORY" in types
      assert body["periodMode"] == "MONTHLY"
      {:ok, %{status: 200, headers: [], body: ~s({"statistics":[]})}}
    end)

    assert {:ok, _} = Tink.CashFlow.query(client)
  end

  test "query/2 overrides defaults with opts" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
      body = Jason.decode!(body_str)
      assert body["periodStart"] == "2024-01"
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    Tink.CashFlow.query(client, period_start: "2024-01")
  end
end
