defmodule Tink.TestHelpers do
  @moduledoc "Shared helpers and fixtures for Tink test modules."

  import Mox
  import ExUnit.Assertions

  alias Tink.Client

  @doc "Build a test client with a predictable token and mock adapter."
  def test_client(opts \\ []) do
    Client.new(
      Keyword.merge(
        [access_token: "test_access_token_abc123", adapter: Tink.HTTP.Mock, cache: false],
        opts
      )
    )
  end

  @doc "Stub the mock adapter to return a successful JSON response."
  def stub_http(body, status \\ 200) do
    stub(Tink.HTTP.Mock, :request, fn _method, _url, _headers, _body, _opts ->
      {:ok, %{status: status, headers: [], body: Jason.encode!(body)}}
    end)
  end

  @doc "Stub the mock adapter to return an error response."
  def stub_http_error(code, message, status \\ 400) do
    stub(Tink.HTTP.Mock, :request, fn _method, _url, _headers, _body, _opts ->
      body = Jason.encode!(%{"errorCode" => code, "errorMessage" => message})
      {:ok, %{status: status, headers: [], body: body}}
    end)
  end

  @doc "Expect exactly one HTTP call with method + URL fragment assertion."
  def expect_http(method, path_fragment, response_body, status \\ 200) do
    expect(Tink.HTTP.Mock, :request, fn m, url, _headers, _body, _opts ->
      assert m == method,
             "Expected HTTP #{inspect(method)} but got #{inspect(m)} for #{url}"

      assert String.contains?(url, path_fragment),
             "Expected URL to contain '#{path_fragment}', got: #{url}"

      {:ok, %{status: status, headers: [], body: Jason.encode!(response_body)}}
    end)
  end

  @doc "Expect a 204 No Content (delete) response."
  def expect_delete(path_fragment) do
    expect(Tink.HTTP.Mock, :request, fn :delete, url, _h, _b, _o ->
      assert String.contains?(url, path_fragment)
      {:ok, %{status: 204, headers: [], body: ""}}
    end)
  end

  # ── Response fixtures ─────────────────────────────────────────────────────────

  def token_response(opts \\ []) do
    %{
      "access_token" => Keyword.get(opts, :access_token, "fake_access_token_xyz"),
      "token_type" => "bearer",
      "expires_in" => Keyword.get(opts, :expires_in, 3600),
      "scope" => Keyword.get(opts, :scope, "accounts:read")
    }
  end

  def account_fixture(id \\ "acc-001") do
    %{
      "id" => id,
      "name" => "Current Account",
      "type" => "CHECKING",
      "identifiers" => %{"iban" => %{"iban" => "GB29NWBK60161331926819"}},
      "balance" => %{"booked" => %{"amount" => %{"currencyCode" => "GBP", "value" => 1500.0}}}
    }
  end

  def transaction_fixture(id \\ "tx-001") do
    %{
      "id" => id,
      "accountId" => "acc-001",
      "amount" => %{"currencyCode" => "GBP", "value" => -9.99},
      "descriptions" => %{"display" => "Spotify", "original" => "SPOTIFY AB"},
      "dates" => %{"booked" => "2024-01-15"},
      "status" => "BOOKED",
      "types" => %{"type" => "DEFAULT"}
    }
  end

  def payment_fixture(id \\ "pay-001") do
    %{
      "id" => id,
      "status" => "PENDING",
      "amount" => %{"currencyCode" => "GBP", "value" => 100.0}
    }
  end
end
