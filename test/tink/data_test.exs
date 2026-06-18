defmodule Tink.UsersTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "create_user/2 posts correct body" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/user/create")
      body = Jason.decode!(body_str)
      assert body["externalUserId"] == "ext-001"
      assert body["market"] == "GB"
      {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"user" => %{"id" => "tink-001"}})}}
    end)

    assert {:ok, %{"user" => %{"id" => "tink-001"}}} =
             Tink.Users.create_user(client, %{external_user_id: "ext-001", market: "GB"})
  end

  test "get_user/1" do
    client = test_client()
    expect_http(:get, "/api/v1/user", %{"id" => "u1"})
    assert {:ok, %{"id" => "u1"}} = Tink.Users.get_user(client)
  end

  test "get_profile/1" do
    client = test_client()
    expect_http(:get, "/api/v1/user/profile", %{"locale" => "en_US"})
    assert {:ok, _} = Tink.Users.get_profile(client)
  end

  test "update_user/2" do
    client = test_client()
    expect_http(:put, "/api/v1/user", %{})
    assert {:ok, _} = Tink.Users.update_user(client, %{"locale" => "sv_SE"})
  end

  test "update_profile/2" do
    client = test_client()
    expect_http(:put, "/api/v1/user/profile", %{})
    assert {:ok, _} = Tink.Users.update_profile(client, %{"notificationSettings" => %{}})
  end

  test "delete_user/2 returns :ok on success" do
    client = test_client()
    stub_http(%{}, 200)
    assert :ok = Tink.Users.delete_user(client, "user-123")
  end
end

defmodule Tink.AccountsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/2 returns accounts" do
    client = test_client()
    stub_http(%{"accounts" => [account_fixture(), account_fixture("acc-002")]})
    assert {:ok, %{"accounts" => [_, _]}} = Tink.Accounts.list(client)
  end

  test "list/2 forwards pageSize and pageToken" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
      assert String.contains?(url, "pageSize=50")
      assert String.contains?(url, "pageToken=cursor_abc")
      {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"accounts" => []})}}
    end)

    Tink.Accounts.list(client, page_size: 50, page_token: "cursor_abc")
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/data/v2/accounts/acc-001", account_fixture("acc-001"))
    assert {:ok, %{"id" => "acc-001"}} = Tink.Accounts.get(client, "acc-001")
  end

  test "get_balances/2" do
    client = test_client()
    resp = %{"booked" => %{"amount" => %{"currencyCode" => "GBP", "value" => 1500.0}}}
    expect_http(:get, "/data/v2/accounts/acc-001/balances", resp)
    assert {:ok, %{"booked" => _}} = Tink.Accounts.get_balances(client, "acc-001")
  end

  test "get_parties/2" do
    client = test_client()
    expect_http(:get, "/data/v2/accounts/acc-001/parties", %{"parties" => []})
    assert {:ok, _} = Tink.Accounts.get_parties(client, "acc-001")
  end

  test "update/3 patches account" do
    client = test_client()
    expect_http(:patch, "/api/v1/accounts/acc-001", account_fixture("acc-001"))
    assert {:ok, _} = Tink.Accounts.update(client, "acc-001", %{"name" => "My Account"})
  end

  test "stream/2 fetches all pages" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
      page =
        if String.contains?(url, "pageToken=p2"),
          do: %{"accounts" => [account_fixture("acc-003")], "nextPageToken" => nil},
          else: %{
            "accounts" => [account_fixture("acc-001"), account_fixture("acc-002")],
            "nextPageToken" => "p2"
          }

      {:ok, %{status: 200, headers: [], body: Jason.encode!(page)}}
    end)

    result = Tink.Accounts.stream(client) |> Enum.to_list()
    assert length(result) == 3
    assert Enum.map(result, & &1["id"]) == ["acc-001", "acc-002", "acc-003"]
  end
end

defmodule Tink.CredentialsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/1" do
    client = test_client()
    expect_http(:get, "/api/v1/credentials/list", %{"credentials" => []})
    assert {:ok, _} = Tink.Credentials.list(client)
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/api/v1/credentials/cred-001", %{"id" => "cred-001"})
    assert {:ok, _} = Tink.Credentials.get(client, "cred-001")
  end

  test "get_qr/2" do
    client = test_client()
    expect_http(:get, "/api/v1/credentials/cred-001/qr", %{"qrCode" => "data:image/png;base64,abc"})
    assert {:ok, _} = Tink.Credentials.get_qr(client, "cred-001")
  end

  test "create/2" do
    client = test_client()
    expect_http(:post, "/api/v1/credentials", %{"id" => "cred-new"})
    assert {:ok, _} = Tink.Credentials.create(client, %{"providerName" => "uk-ob-monzo"})
  end

  test "delete/2 returns :ok" do
    client = test_client()
    expect_delete("/api/v1/credentials/cred-001")
    assert :ok = Tink.Credentials.delete(client, "cred-001")
  end

  test "refresh/2" do
    client = test_client()
    expect_http(:post, "/api/v1/credentials/cred-001/refresh", %{})
    assert {:ok, _} = Tink.Credentials.refresh(client, "cred-001")
  end

  test "authenticate/2" do
    client = test_client()
    expect_http(:post, "/api/v1/credentials/cred-001/authenticate", %{})
    assert {:ok, _} = Tink.Credentials.authenticate(client, "cred-001")
  end

  test "submit_supplemental_info/3" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/credentials/cred-001/supplemental-information")
      body = Jason.decode!(body_str)
      assert body["information"] == [%{"name" => "otp", "value" => "123456"}]
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    assert {:ok, _} =
             Tink.Credentials.submit_supplemental_info(
               client,
               "cred-001",
               [%{"name" => "otp", "value" => "123456"}]
             )
  end
end

defmodule Tink.TransactionsTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list/2 returns transactions" do
    client = test_client()
    stub_http(%{"transactions" => [transaction_fixture(), transaction_fixture("tx-002")]})
    assert {:ok, %{"transactions" => [_, _]}} = Tink.Transactions.list(client)
  end

  test "list/2 forwards date filters" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
      assert String.contains?(url, "bookedDateGte=2024-01-01")
      assert String.contains?(url, "bookedDateLte=2024-12-31")
      {:ok, %{status: 200, headers: [], body: ~s({"transactions":[]})}}
    end)

    Tink.Transactions.list(client, booked_date_gte: "2024-01-01", booked_date_lte: "2024-12-31")
  end

  test "get/2" do
    client = test_client()
    expect_http(:get, "/api/v1/transactions/tx-001", transaction_fixture())
    assert {:ok, %{"id" => "tx-001"}} = Tink.Transactions.get(client, "tx-001")
  end

  test "get_similar/2" do
    client = test_client()
    expect_http(:get, "/api/v1/transactions/tx-001/similar", %{"transactions" => []})
    assert {:ok, _} = Tink.Transactions.get_similar(client, "tx-001")
  end

  test "search/2" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/search")
      body = Jason.decode!(body_str)
      assert body["queryString"] == "spotify"
      {:ok, %{status: 200, headers: [], body: ~s({"results":[]})}}
    end)

    assert {:ok, _} = Tink.Transactions.search(client, query_string: "spotify")
  end

  test "suggest/2" do
    client = test_client()
    expect_http(:get, "/api/v1/transactions/suggest", %{"suggestions" => []})
    assert {:ok, _} = Tink.Transactions.suggest(client, "spot")
  end

  test "update/3" do
    client = test_client()
    expect_http(:put, "/api/v1/transactions/tx-001", transaction_fixture())
    assert {:ok, _} = Tink.Transactions.update(client, "tx-001", %{"categoryId" => "cat-123"})
  end

  test "categorize_multiple/2" do
    client = test_client()

    expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body_str, _o ->
      assert String.contains?(url, "/api/v1/transactions/categorize-multiple")
      body = Jason.decode!(body_str)
      assert length(body["categorizationList"]) == 2
      {:ok, %{status: 200, headers: [], body: ~s({})}}
    end)

    assert {:ok, _} =
             Tink.Transactions.categorize_multiple(client, [
               %{"id" => "tx-001", "categoryId" => "c1"},
               %{"id" => "tx-002", "categoryId" => "c2"}
             ])
  end

  test "stream/2 aggregates across pages" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
      page =
        if String.contains?(url, "pageToken=p2"),
          do: %{"transactions" => [transaction_fixture("tx-003")], "nextPageToken" => nil},
          else: %{
            "transactions" => [transaction_fixture("tx-001"), transaction_fixture("tx-002")],
            "nextPageToken" => "p2"
          }

      {:ok, %{status: 200, headers: [], body: Jason.encode!(page)}}
    end)

    result = Tink.Transactions.stream(client) |> Enum.to_list()
    assert length(result) == 3
  end

  test "list_all/2 collects all pages" do
    client = test_client()

    stub(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
      page =
        if String.contains?(url, "pageToken=p2"),
          do: %{"transactions" => [transaction_fixture("tx-003")], "nextPageToken" => nil},
          else: %{"transactions" => [transaction_fixture("tx-001")], "nextPageToken" => "p2"}

      {:ok, %{status: 200, headers: [], body: Jason.encode!(page)}}
    end)

    assert {:ok, txns} = Tink.Transactions.list_all(client)
    assert length(txns) == 2
  end
end

defmodule Tink.ProvidersTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "list_markets/1" do
    client = test_client()
    expect_http(:get, "/api/v1/providers/markets", %{"markets" => ["GB", "SE"]})
    assert {:ok, %{"markets" => _}} = Tink.Providers.list_markets(client)
  end

  test "list_for_market/3" do
    client = test_client()
    expect_http(:get, "/api/v1/providers/GB", %{"providers" => []})
    assert {:ok, _} = Tink.Providers.list_for_market(client, "GB")
  end

  test "get/2" do
    client = test_client()

    expect_http(:get, "/api/v1/providers/uk-ob-monzo", %{
      "name" => "uk-ob-monzo",
      "status" => "ENABLED"
    })

    assert {:ok, _} = Tink.Providers.get(client, "uk-ob-monzo")
  end

  test "list_identifiers/1" do
    client = test_client()
    expect_http(:get, "/api/v1/provider-identifiers", %{"identifiers" => []})
    assert {:ok, _} = Tink.Providers.list_identifiers(client)
  end

  test "get_auth_options/2" do
    client = test_client()
    expect_http(:get, "/api/v1/provider-authentication-options/uk-ob-monzo", %{"options" => []})
    assert {:ok, _} = Tink.Providers.get_auth_options(client, "uk-ob-monzo")
  end

  test "get_auth_options_for_market/2" do
    client = test_client()
    expect_http(:get, "/api/v1/provider-authentication-options-for-market/GB", %{"providers" => []})
    assert {:ok, _} = Tink.Providers.get_auth_options_for_market(client, "GB")
  end
end
