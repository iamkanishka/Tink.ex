# Testing

Tink is designed to be easily testable. This guide covers unit testing with
Mox, integration testing with Bypass, and using Tink's sandbox environment.

## Unit Testing with Mox

Tink defines `Tink.HTTPBehaviour` so you can mock the HTTP layer:

```elixir
# test/support/mocks.ex
Mox.defmock(Tink.HTTPMock, for: Tink.HTTPBehaviour)
```

```elixir
# config/test.exs
config :tink,
  http_adapter:         Tink.HTTPMock,
  enable_rate_limiting: false,
  cache:                [enabled: false]
```

```elixir
# test/my_feature_test.exs
defmodule MyFeatureTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "lists accounts" do
    Tink.HTTPMock
    |> expect(:get, fn _client, "/api/v1/accounts", _opts ->
      {:ok, %{
        "accounts" => [
          %{"id" => "acc_1", "name" => "Current Account", "balance" => 1500}
        ]
      }}
    end)

    {:ok, client} = Tink.Client.new(client_id: "test", client_secret: "test")
    assert {:ok, [%{id: "acc_1"}]} = Tink.Accounts.list(client)
  end
end
```

## Integration Testing with Bypass

Use [Bypass](https://hex.pm/packages/bypass) to run a local HTTP server that
intercepts real Finch requests:

```elixir
defmodule Tink.AccountsIntegrationTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    client = Tink.Client.new!(
      client_id:     "test_id",
      client_secret: "test_secret",
      base_url:      "http://localhost:#{bypass.port}"
    )
    {:ok, bypass: bypass, client: client}
  end

  test "lists accounts", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/api/v1/accounts", fn conn ->
      Plug.Conn.resp(conn, 200, Jason.encode!(%{
        "accounts" => [%{"id" => "acc_1", "name" => "Checking"}]
      }))
    end)

    assert {:ok, [%{id: "acc_1"}]} = Tink.Accounts.list(client)
  end
end
```

## Sandbox Environment

Tink provides a sandbox for end-to-end testing without real banks:

```elixir
# config/test.exs
config :tink,
  base_url:      "https://api.tink.com",   # Sandbox uses the same base URL
  client_id:     System.get_env("TINK_SANDBOX_CLIENT_ID"),
  client_secret: System.get_env("TINK_SANDBOX_CLIENT_SECRET")
```

In the sandbox you can use Tink's test providers (e.g. `se-test-open-banking-redirect`)
to simulate bank connections without real credentials.

## Test Helpers

Disable rate limiting and caching in tests to avoid flakiness:

```elixir
# config/test.exs
config :tink,
  enable_rate_limiting: false,
  cache: [enabled: false],
  debug_mode: false
```

## Property-Based Testing

Use `stream_data` to fuzz-test parameter handling:

```elixir
defmodule Tink.ParamTest do
  use ExUnit.Case
  use ExUnitProperties

  property "list_transactions/2 never raises on arbitrary date strings" do
    check all date <- StreamData.string(:alphanumeric, max_length: 20) do
      result = Tink.Transactions.list(client(), date_from: date)
      assert match?({:ok, _} | {:error, %Tink.Error{}}, result)
    end
  end
end
```
