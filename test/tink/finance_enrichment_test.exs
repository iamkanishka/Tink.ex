defmodule Tink.BudgetsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create/2 invalidates list cache" do
    client = test_client()
    expect_http(:post, "/api/v1/budgets", %{"id" => "bud-001"})
    assert {:ok, _} = Tink.Budgets.create(client, %{name: "Groceries"})
  end

  test "create_one_off/2" do
    client = test_client()
    expect_http(:post, "/api/v1/budgets/one-off", %{"id" => "bud-002"})
    assert {:ok, _} = Tink.Budgets.create_one_off(client, %{})
  end

  test "create_recurring/2" do
    client = test_client()
    expect_http(:post, "/api/v1/budgets/recurring", %{"id" => "bud-003"})
    assert {:ok, _} = Tink.Budgets.create_recurring(client, %{})
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/api/v1/budgets/bud-001", %{"id" => "bud-001"})
    assert {:ok, _} = Tink.Budgets.get(client, "bud-001")
  end

  test "get_details/2" do
    client = test_client()
    expect_http(:get, "/api/v1/budgets/bud-001/details", %{"periods" => []})
    assert {:ok, _} = Tink.Budgets.get_details(client, "bud-001")
  end

  test "get_transactions/2" do
    client = test_client()
    expect_http(:get, "/api/v1/budgets/bud-001/transactions", %{"transactions" => []})
    assert {:ok, _} = Tink.Budgets.get_transactions(client, "bud-001")
  end

  test "list/1" do
    client = test_client()
    expect_http(:get, "/api/v1/budgets", %{"budgets" => []})
    assert {:ok, _} = Tink.Budgets.list(client)
  end

  test "list_summaries/1" do
    client = test_client()
    expect_http(:get, "/api/v1/budgets/summaries", %{"summaries" => []})
    assert {:ok, _} = Tink.Budgets.list_summaries(client)
  end

  test "list_recommended/1" do
    client = test_client()
    expect_http(:get, "/api/v1/budgets/recommended", %{"budgets" => []})
    assert {:ok, _} = Tink.Budgets.list_recommended(client)
  end

  test "update/3" do
    client = test_client()
    expect_http(:put, "/api/v1/budgets/bud-001", %{"id" => "bud-001"})
    assert {:ok, _} = Tink.Budgets.update(client, "bud-001", %{name: "Food"})
  end

  test "archive/2" do
    client = test_client()
    expect_http(:post, "/api/v1/budgets/bud-001/archive", %{})
    assert {:ok, _} = Tink.Budgets.archive(client, "bud-001")
  end

  test "delete/2 returns :ok" do
    client = test_client()
    expect_delete("/api/v1/budgets/bud-001")
    assert :ok = Tink.Budgets.delete(client, "bud-001")
  end
end

defmodule Tink.SavingsGoalsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1" do
    client = test_client()
    expect_http(:get, "/api/v1/savings-goals", %{"savingsGoals" => []})
    assert {:ok, _} = Tink.SavingsGoals.list(client)
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/api/v1/savings-goals/sg-001", %{"id" => "sg-001"})
    assert {:ok, _} = Tink.SavingsGoals.get(client, "sg-001")
  end

  test "get_period_progress/2" do
    client = test_client()
    expect_http(:get, "/api/v1/savings-goals/sg-001/period_progress", %{})
    assert {:ok, _} = Tink.SavingsGoals.get_period_progress(client, "sg-001")
  end

  test "list_allocations/2" do
    client = test_client()
    expect_http(:get, "/api/v1/savings-goals/sg-001/allocations", %{"allocations" => []})
    assert {:ok, _} = Tink.SavingsGoals.list_allocations(client, "sg-001")
  end

  test "list_accounts/1" do
    client = test_client()
    expect_http(:get, "/api/v1/savings-goals/accounts", %{"accounts" => []})
    assert {:ok, _} = Tink.SavingsGoals.list_accounts(client)
  end

  test "list_account_allocations/2" do
    client = test_client()
    expect_http(:get, "/api/v1/savings-goals/accounts/acc-001/allocations", %{})
    assert {:ok, _} = Tink.SavingsGoals.list_account_allocations(client, "acc-001")
  end

  test "list_categories/1" do
    client = test_client()
    expect_http(:get, "/api/v1/savings-goals/categories", %{"categories" => []})
    assert {:ok, _} = Tink.SavingsGoals.list_categories(client)
  end

  test "create/2" do
    client = test_client()
    expect_http(:post, "/api/v1/savings-goals", %{"id" => "sg-001"})
    assert {:ok, _} = Tink.SavingsGoals.create(client, %{name: "Holiday"})
  end

  test "update/3" do
    client = test_client()
    expect_http(:put, "/api/v1/savings-goals/sg-001", %{})
    assert {:ok, _} = Tink.SavingsGoals.update(client, "sg-001", %{name: "Euro Trip"})
  end

  test "archive/2" do
    client = test_client()
    expect_http(:post, "/api/v1/savings-goals/sg-001:archive", %{})
    assert {:ok, _} = Tink.SavingsGoals.archive(client, "sg-001")
  end

  test "complete/2" do
    client = test_client()
    expect_http(:post, "/api/v1/savings-goals/sg-001:complete", %{})
    assert {:ok, _} = Tink.SavingsGoals.complete(client, "sg-001")
  end

  test "deposit/3" do
    client = test_client()
    expect_http(:post, "/api/v1/savings-goals/sg-001/allocations/fund:deposit", %{})
    assert {:ok, _} = Tink.SavingsGoals.deposit(client, "sg-001", %{amount: 100})
  end

  test "withdraw/3" do
    client = test_client()
    expect_http(:post, "/api/v1/savings-goals/sg-001/allocations/fund:withdraw", %{})
    assert {:ok, _} = Tink.SavingsGoals.withdraw(client, "sg-001", %{amount: 50})
  end

  test "reallocate/2" do
    client = test_client()
    expect_http(:post, "/api/v1/savings-goals/allocations/fund:reallocate", %{})
    assert {:ok, _} = Tink.SavingsGoals.reallocate(client, %{from: "sg-001", to: "sg-002"})
  end
end

defmodule Tink.EnrichmentTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "Categories.list/2 returns categories" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/categories", %{"categories" => [%{"id" => "c1"}]})
    assert {:ok, %{"categories" => [_]}} = Tink.Enrichment.Categories.list(client)
  end

  test "Transactions.list/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/transactions", %{"transactions" => []})
    assert {:ok, _} = Tink.Enrichment.Transactions.list(client)
  end

  test "Transactions.list_by_ids/2 posts IDs" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/enrichment/v1/transactions-by-ids")
      body = Jason.decode!(body_str)
      assert body["ids"] == ["tx-001", "tx-002"]
      {:ok, %{status: 200, headers: [], body: ~s({"transactions":[]})}}
    end)

    assert {:ok, _} = Tink.Enrichment.Transactions.list_by_ids(client, ["tx-001", "tx-002"])
  end

  test "Transactions.find_similar/3" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/transactions/tx-001:find-similar", %{"transactions" => []})
    assert {:ok, _} = Tink.Enrichment.Transactions.find_similar(client, "tx-001")
  end

  test "Transactions.submit_feedback/2" do
    client = test_client()
    expect_http(:post, "/enrichment/v1/feedback", %{})

    assert {:ok, _} =
             Tink.Enrichment.Transactions.submit_feedback(client, %{transactionId: "tx-001"})
  end

  test "Recurring.list_groups/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/recurring-transactions-groups", %{"groups" => []})
    assert {:ok, _} = Tink.Enrichment.Recurring.list_groups(client)
  end

  test "Recurring.get_group/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/recurring-transactions-groups/g-001", %{"id" => "g-001"})
    assert {:ok, _} = Tink.Enrichment.Recurring.get_group(client, "g-001")
  end

  test "Recurring.list/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/recurring-transactions", %{"transactions" => []})
    assert {:ok, _} = Tink.Enrichment.Recurring.list(client)
  end

  test "Recurring.list_predicted/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/predicted-recurring-transactions", %{"transactions" => []})
    assert {:ok, _} = Tink.Enrichment.Recurring.list_predicted(client)
  end

  test "Merchants.get_brand/2" do
    client = test_client()

    expect_http(:get, "/enrichment/v1/brand-identification/brands/brand-001", %{"id" => "brand-001"})

    assert {:ok, _} = Tink.Enrichment.Merchants.get_brand(client, "brand-001")
  end

  test "Merchants.get_merchant/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/brand-identification/merchants/m-001", %{"id" => "m-001"})
    assert {:ok, _} = Tink.Enrichment.Merchants.get_merchant(client, "m-001")
  end

  test "OnDemand.enrich/2 posts transactions" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/enrichment/v1/transactions/on-demand")
      body = Jason.decode!(body_str)
      assert length(body["transactions"]) == 1
      {:ok, %{status: 200, headers: [], body: ~s({"transactions":[]})}}
    end)

    assert {:ok, _} = Tink.Enrichment.OnDemand.enrich(client, [%{"description" => "Spotify"}])
  end

  test "Sustainability.get_insights/1" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/sustainability/insights", %{})
    assert {:ok, _} = Tink.Enrichment.Sustainability.get_insights(client)
  end

  test "Sustainability.get_user_insights/1" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/sustainability/users/insights", %{})
    assert {:ok, _} = Tink.Enrichment.Sustainability.get_user_insights(client)
  end

  test "Sustainability.get_market_average/1" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/sustainability/market-average", %{})
    assert {:ok, _} = Tink.Enrichment.Sustainability.get_market_average(client)
  end

  test "Sustainability.get_transaction/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/sustainability/transactions/tx-001", %{})
    assert {:ok, _} = Tink.Enrichment.Sustainability.get_transaction(client, "tx-001")
  end

  test "Sustainability.get_transaction_comparables/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/sustainability/transactions/tx-001/comparables", %{})
    assert {:ok, _} = Tink.Enrichment.Sustainability.get_transaction_comparables(client, "tx-001")
  end

  test "Sustainability.get_transaction_refinement/2" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/sustainability/transactions/tx-001/refinement", %{})
    assert {:ok, _} = Tink.Enrichment.Sustainability.get_transaction_refinement(client, "tx-001")
  end

  test "Sustainability.get_user_profiling/1" do
    client = test_client()
    expect_http(:get, "/enrichment/v1/sustainability/users/profiling", %{})
    assert {:ok, _} = Tink.Enrichment.Sustainability.get_user_profiling(client)
  end

  test "Sustainability.get_profiling_questions/1" do
    client = test_client()

    expect_http(:get, "/enrichment/v1/sustainability/users/profiling/questions", %{
      "questions" => []
    })

    assert {:ok, _} = Tink.Enrichment.Sustainability.get_profiling_questions(client)
  end
end

defmodule Tink.InsightsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1" do
    client = test_client()
    expect_http(:get, "/api/v1/insights", %{"insights" => []})
    assert {:ok, _} = Tink.Insights.list(client)
  end

  test "list_archived/1" do
    client = test_client()
    expect_http(:get, "/api/v1/insights/archived", %{"insights" => []})
    assert {:ok, _} = Tink.Insights.list_archived(client)
  end

  test "archive/2" do
    client = test_client()
    expect_http(:post, "/api/v1/insights/ins-001/archive", %{})
    assert {:ok, _} = Tink.Insights.archive(client, "ins-001")
  end

  test "take_action/2" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/insights/action")
      body = Jason.decode!(body_str)
      assert body["insightId"] == "ins-001"
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    assert {:ok, _} =
             Tink.Insights.take_action(client, %{"insightId" => "ins-001", "type" => "ACKNOWLEDGE"})
  end
end
