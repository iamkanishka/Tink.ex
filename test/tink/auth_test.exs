defmodule Tink.AuthTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers

  setup :verify_on_exit!

  describe "client_credentials/1" do
    test "returns a Client on success" do
      expect(Tink.HTTP.Mock, :request, fn :post, url, _h, body, _o ->
        assert String.contains?(url, "/api/v1/oauth/token")
        assert String.contains?(body, "grant_type=client_credentials")
        assert String.contains?(body, "scope=authorization%3Agrant")
        {:ok, %{status: 200, headers: [], body: Jason.encode!(token_response())}}
      end)

      assert {:ok, client} = Tink.Auth.client_credentials(scope: "authorization:grant")
      assert client.access_token == "fake_access_token_xyz"
      assert %DateTime{} = client.expires_at
      assert client.scope == "accounts:read"
    end

    test "raises when scope is missing" do
      assert_raise KeyError, fn ->
        Tink.Auth.client_credentials([])
      end
    end

    test "returns error on 401" do
      stub_http_error("AUTHENTICATION_ERROR", "Invalid credentials", 401)

      assert {:error, %Tink.Error{status: 401, code: "AUTHENTICATION_ERROR"}} =
               Tink.Auth.client_credentials(scope: "authorization:grant")
    end

    test "does not retry 401" do
      # max_retries is 0 in test config so only one call should be made
      expect(Tink.HTTP.Mock, :request, 1, fn :post, _url, _h, _body, _o ->
        {:ok, %{status: 401, headers: [], body: Jason.encode!(%{"errorCode" => "UNAUTHORIZED"})}}
      end)

      assert {:error, %Tink.Error{status: 401}} =
               Tink.Auth.client_credentials(scope: "authorization:grant")
    end
  end

  describe "user_client/2" do
    test "exchanges code for user token" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body, _o ->
        assert String.contains?(body, "grant_type=authorization_code")
        assert String.contains?(body, "code=test_code")

        {:ok,
         %{
           status: 200,
           headers: [],
           body: Jason.encode!(token_response(scope: "accounts:read,transactions:read"))
         }}
      end)

      assert {:ok, client} = Tink.Auth.user_client("test_code")
      assert client.access_token == "fake_access_token_xyz"
    end

    test "requires a binary code" do
      assert_raise FunctionClauseError, fn ->
        Tink.Auth.user_client(nil)
      end
    end
  end

  describe "create_authorization/2" do
    test "posts to authorization-grant with user_id and scope as form-urlencoded" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, url, headers, body_str, _o ->
        assert String.contains?(url, "/api/v1/oauth/authorization-grant")
        assert {"content-type", "application/x-www-form-urlencoded"} in headers
        decoded = URI.decode_query(body_str)
        assert decoded["user_id"] == "user-123"
        assert decoded["scope"] == "accounts:read,transactions:read"
        {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"code" => "grant_code_abc"})}}
      end)

      assert {:ok, %{"code" => "grant_code_abc"}} =
               Tink.Auth.create_authorization(client,
                 user_id: "user-123",
                 scope: "accounts:read,transactions:read"
               )
    end

    test "posts with external_user_id" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
        decoded = URI.decode_query(body_str)
        assert decoded["external_user_id"] == "ext-user-456"
        refute Map.has_key?(decoded, "user_id")
        {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"code" => "grant_ext"})}}
      end)

      assert {:ok, %{"code" => "grant_ext"}} =
               Tink.Auth.create_authorization(client,
                 external_user_id: "ext-user-456",
                 scope: "accounts:read"
               )
    end

    test "nil fields are omitted from request body" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
        decoded = URI.decode_query(body_str)
        refute Map.has_key?(decoded, "id_hint")
        refute Map.has_key?(decoded, "external_user_id")
        {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"code" => "c"})}}
      end)

      Tink.Auth.create_authorization(client, user_id: "u", scope: "s")
    end
  end

  describe "delegate_authorization/2" do
    test "posts to authorization-grant/delegate as form-urlencoded with actor_client_id" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, url, headers, body_str, _o ->
        assert String.contains?(url, "/api/v1/oauth/authorization-grant/delegate")
        assert {"content-type", "application/x-www-form-urlencoded"} in headers
        decoded = URI.decode_query(body_str)
        assert decoded["external_user_id"] == "ext-user-456"
        assert decoded["actor_client_id"] == "df05e4b379934cd09963197cc855bfe9"
        assert decoded["id_hint"] == "Tom John"
        assert decoded["scope"] == "consents,consents:readonly"
        {:ok, %{status: 200, headers: [], body: Jason.encode!(%{"code" => "delegated_code"})}}
      end)

      assert {:ok, %{"code" => "delegated_code"}} =
               Tink.Auth.delegate_authorization(client,
                 external_user_id: "ext-user-456",
                 actor_client_id: "df05e4b379934cd09963197cc855bfe9",
                 id_hint: "Tom John",
                 scope: "consents,consents:readonly"
               )
    end
  end

  describe "revoke_all/1" do
    test "posts to revoke-all endpoint" do
      client = test_client()
      expect_http(:post, "/api/v1/oauth/revoke-all", %{})
      assert {:ok, _} = Tink.Auth.revoke_all(client)
    end
  end

  describe "inspect_token/1" do
    test "gets token check endpoint" do
      client = test_client()
      expect_http(:get, "/api/v1/oauth/token/check", %{"scope" => "accounts:read"})
      assert {:ok, %{"scope" => "accounts:read"}} = Tink.Auth.inspect_token(client)
    end
  end

  describe "token TTL defaults" do
    test "client_credentials uses 1800s default when expires_in is absent" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _body, _o ->
        # Response WITHOUT expires_in field
        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(%{
               "access_token" => "tok",
               "token_type" => "bearer",
               "scope" => "accounts:read"
             })
         }}
      end)

      {:ok, client} = Tink.Auth.client_credentials(scope: "accounts:read")
      secs = Tink.AuthToken.seconds_until_expiry(client)
      # Should be close to 1800 (30 min)
      assert secs > 1750 and secs <= 1800
    end

    test "user_client uses 7200s default when expires_in is absent" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _body, _o ->
        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(%{
               "access_token" => "tok",
               "token_type" => "bearer",
               "scope" => "accounts:read"
             })
         }}
      end)

      {:ok, client} = Tink.Auth.user_client("code123")
      secs = Tink.AuthToken.seconds_until_expiry(client)
      # Should be close to 7200 (2 hours)
      assert secs > 7150 and secs <= 7200
    end

    test "explicit expires_in from response overrides default" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _body, _o ->
        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(%{
               "access_token" => "tok",
               "expires_in" => 60,
               "scope" => "accounts:read"
             })
         }}
      end)

      {:ok, client} = Tink.Auth.client_credentials(scope: "accounts:read")
      secs = Tink.AuthToken.seconds_until_expiry(client)
      assert secs > 50 and secs <= 60
    end
  end

  describe "refresh_token and id_hint capture" do
    test "captures refresh_token when present in response" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _body, _o ->
        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(%{
               "access_token" => "tok",
               "refresh_token" => "refresh-abc",
               "scope" => "accounts:read"
             })
         }}
      end)

      {:ok, client} = Tink.Auth.user_client("code123")
      assert client.refresh_token == "refresh-abc"
    end

    test "refresh_token is nil when absent from response" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _body, _o ->
        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(%{
               "access_token" => "tok",
               "scope" => "accounts:read"
             })
         }}
      end)

      {:ok, client} = Tink.Auth.client_credentials(scope: "accounts:read")
      assert is_nil(client.refresh_token)
    end

    test "captures id_hint when present in response" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _body, _o ->
        {:ok,
         %{
           status: 200,
           headers: [],
           body:
             Jason.encode!(%{
               "access_token" => "tok",
               "id_hint" => "user@example.com",
               "scope" => "accounts:read"
             })
         }}
      end)

      {:ok, client} = Tink.Auth.user_client("code123")
      assert client.id_hint == "user@example.com"
    end
  end

  describe "rate_limit_key auto-population" do
    test "client built via client_credentials gets rate_limit_key from config client_id" do
      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, _body, _o ->
        {:ok, %{status: 200, headers: [], body: Jason.encode!(token_response())}}
      end)

      {:ok, client} = Tink.Auth.client_credentials(scope: "accounts:read")
      # config/test.exs sets client_id to "test_client_id"
      assert client.rate_limit_key == "test_client_id"
    end
  end

  describe "refresh/3" do
    test "posts refresh_token grant" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
        assert String.contains?(body_str, "grant_type=refresh_token")
        assert String.contains?(body_str, "refresh_token=old-refresh-token")

        {:ok,
         %{status: 200, headers: [], body: Jason.encode!(token_response(scope: "accounts:read"))}}
      end)

      assert {:ok, new_client} = Tink.Auth.refresh(client, "old-refresh-token")
      assert new_client.access_token == "fake_access_token_xyz"
    end
  end
end
