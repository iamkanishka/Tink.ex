defmodule TinkTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers
  setup :verify_on_exit!

  test "app_client/2 delegates to Auth.client_credentials" do
    expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
      assert String.contains?(body_str, "grant_type=client_credentials")
      {:ok, %{status: 200, headers: [], body: Jason.encode!(token_response())}}
    end)

    assert {:ok, %Tink.Client{}} = Tink.app_client("authorization:grant")
  end

  test "user_client/2 delegates to Auth.user_client" do
    expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
      assert String.contains?(body_str, "grant_type=authorization_code")
      {:ok, %{status: 200, headers: [], body: Jason.encode!(token_response())}}
    end)

    assert {:ok, %Tink.Client{}} = Tink.user_client("redirect_code")
  end
end
