defmodule Tink.ClientTest do
  use ExUnit.Case, async: true
  import Mox
  import Tink.TestHelpers

  setup :verify_on_exit!

  describe "new/1" do
    test "builds a Client struct" do
      client = Tink.Client.new(access_token: "tok123")
      assert client.access_token == "tok123"
      assert client.token_type == "bearer"
      assert client.cache == true
      assert client.auto_refresh == false
    end

    test "raises when access_token is missing" do
      assert_raise KeyError, fn -> Tink.Client.new([]) end
    end
  end

  describe "expired?/1" do
    test "false for nil expires_at" do
      refute Tink.Client.expired?(test_client())
    end

    test "true for past expires_at" do
      client = test_client(expires_at: DateTime.add(DateTime.utc_now(), -10, :second))
      assert Tink.Client.expired?(client)
    end

    test "false for future expires_at" do
      client = test_client(expires_at: DateTime.add(DateTime.utc_now(), 3600, :second))
      refute Tink.Client.expired?(client)
    end
  end

  describe "cache_enabled?/1" do
    test "returns false when client.cache is false" do
      client = test_client(cache: false)
      refute Tink.Client.cache_enabled?(client)
    end

    test "returns false when global config disables cache (test config)" do
      # config/test.exs sets cache: [enabled: false]
      client = test_client(cache: true)
      refute Tink.Client.cache_enabled?(client)
    end
  end

  describe "add_query/2" do
    test "appends query string" do
      assert Tink.Client.add_query("/path", %{"foo" => "bar"}) == "/path?foo=bar"
    end

    test "filters nil values" do
      result = Tink.Client.add_query("/path", %{"a" => "1", "b" => nil})
      assert result == "/path?a=1"
    end

    test "returns path unchanged for empty params" do
      assert Tink.Client.add_query("/path", %{}) == "/path"
      assert Tink.Client.add_query("/path", []) == "/path"
    end

    test "handles keyword list" do
      result = Tink.Client.add_query("/p", pageSize: 50, pageToken: "tok")
      assert String.contains?(result, "pageSize=50")
      assert String.contains?(result, "pageToken=tok")
    end
  end

  describe "HTTP methods" do
    test "get/2 makes GET request" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :get, url, _h, _b, _o ->
        assert String.contains?(url, "/api/v1/test")
        {:ok, %{status: 200, headers: [], body: ~s({"ok":true})}}
      end)

      assert {:ok, %{"ok" => true}} = Tink.Client.get(client, "/api/v1/test")
    end

    test "post/3 sends JSON body" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, headers, body_str, _o ->
        assert Enum.any?(headers, fn {k, v} ->
                 k == "content-type" and String.contains?(v, "json")
               end)

        body = Jason.decode!(body_str)
        assert body["name"] == "test"
        {:ok, %{status: 201, headers: [], body: ~s({"id":"new-001"})}}
      end)

      assert {:ok, %{"id" => "new-001"}} =
               Tink.Client.post(client, "/api/v1/r", %{"name" => "test"})
    end

    test "delete/2 returns {:ok, %{}} on 204" do
      client = test_client()

      stub(Tink.HTTP.Mock, :request, fn :delete, _url, _h, _b, _o ->
        {:ok, %{status: 204, headers: [], body: ""}}
      end)

      assert {:ok, %{}} = Tink.Client.delete(client, "/api/v1/r/1")
    end

    test "returns {:error, %Tink.Error{}} on 404" do
      client = test_client()
      stub_http_error("NOT_FOUND", "Resource not found", 404)

      assert {:error, %Tink.Error{status: 404, code: "NOT_FOUND"}} =
               Tink.Client.get(client, "/api/v1/missing")
    end

    test "sends form-encoded body when content_type is form" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, _h, body_str, _o ->
        assert String.contains?(body_str, "grant_type=client_credentials")
        {:ok, %{status: 200, headers: [], body: ~s({})}}
      end)

      Tink.Client.post(client, "/token", %{"grant_type" => "client_credentials"},
        content_type: "application/x-www-form-urlencoded"
      )
    end

    test "includes x-tink-request-id in error" do
      client = test_client()

      stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        {:ok,
         %{
           status: 400,
           headers: [{"x-tink-request-id", "req-abc-123"}],
           body: Jason.encode!(%{"errorCode" => "BAD_REQUEST", "errorMessage" => "bad"})
         }}
      end)

      assert {:error, %Tink.Error{request_id: "req-abc-123"}} =
               Tink.Client.get(client, "/api/v1/fail")
    end

    test "does not retry 400" do
      client = test_client()
      # Should be called exactly once — 400 is non-retryable
      expect(Tink.HTTP.Mock, :request, 1, fn :get, _url, _h, _b, _o ->
        {:ok, %{status: 400, headers: [], body: ~s({"errorCode":"BAD_REQUEST"})}}
      end)

      Tink.Client.get(client, "/api/v1/bad")
    end

    test "network error produces NETWORK_ERROR" do
      client = test_client()

      stub(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        {:error, :econnrefused}
      end)

      assert {:error, %Tink.Error{status: nil, code: "NETWORK_ERROR"}} =
               Tink.Client.get(client, "/api/v1/test")
    end
  end

  describe "rate_limit_key" do
    test "nil rate_limit_key bypasses rate limit check" do
      # Rate limiting is disabled in test config, so any request should pass
      client = test_client(rate_limit_key: nil)

      expect(Tink.HTTP.Mock, :request, fn :get, _url, _h, _b, _o ->
        {:ok, %{status: 200, headers: [], body: ~s({"ok":true})}}
      end)

      assert {:ok, _} = Tink.Client.get(client, "/api/v1/test")
    end

    test "rate_limit_key is stored on client" do
      client = Tink.Client.new(access_token: "tok", rate_limit_key: "my-app-id")
      assert client.rate_limit_key == "my-app-id"
    end
  end

  describe "X-Client-Trace-ID header" do
    test "is sent when client_trace_id option is provided" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :get, _url, headers, _b, _o ->
        header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
        assert header_map["x-client-trace-id"] == "trace-abc-123"
        {:ok, %{status: 200, headers: [], body: ~s({})}}
      end)

      Tink.Client.get(client, "/api/v1/test", client_trace_id: "trace-abc-123")
    end

    test "is omitted when client_trace_id option is not provided" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :get, _url, headers, _b, _o ->
        header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
        refute Map.has_key?(header_map, "x-client-trace-id")
        {:ok, %{status: 200, headers: [], body: ~s({})}}
      end)

      Tink.Client.get(client, "/api/v1/test")
    end
  end

  describe "Idempotency-Key header" do
    test "is sent when idempotency_key option is provided" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, headers, _b, _o ->
        header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
        assert header_map["idempotency-key"] == "idem-key-001"
        {:ok, %{status: 200, headers: [], body: ~s({})}}
      end)

      Tink.Client.post(client, "/api/v1/payments/requests", %{}, idempotency_key: "idem-key-001")
    end

    test "is omitted when idempotency_key option is not provided" do
      client = test_client()

      expect(Tink.HTTP.Mock, :request, fn :post, _url, headers, _b, _o ->
        header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
        refute Map.has_key?(header_map, "idempotency-key")
        {:ok, %{status: 200, headers: [], body: ~s({})}}
      end)

      Tink.Client.post(client, "/api/v1/r", %{})
    end
  end

  describe "Retry-After respecting 429 response" do
    test "uses retryAfterMillis from error body when retrying 429" do
      client = test_client()
      call_count = :counters.new(1, [:atomics])

      expect(Tink.HTTP.Mock, :request, 2, fn :get, _url, _h, _b, _o ->
        :counters.add(call_count, 1, 1)
        n = :counters.get(call_count, 1)

        if n == 1 do
          {:ok,
           %{
             status: 429,
             headers: [],
             body:
               Jason.encode!(%{
                 "errorCode" => "TOO_MANY_REQUESTS",
                 "retryAfterMillis" => 5
               })
           }}
        else
          {:ok, %{status: 200, headers: [], body: ~s({"ok":true})}}
        end
      end)

      assert {:ok, %{"ok" => true}} = Tink.Client.get(client, "/api/v1/test", max_retries: 2)
      assert :counters.get(call_count, 1) == 2
    end
  end
end
