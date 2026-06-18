defmodule Tink.AuthTokenTest do
  use ExUnit.Case, async: true

  alias Tink.{AuthToken, Client}

  defp client_with_scope(scope) do
    Client.new(access_token: "test_token_abc", scope: scope)
  end

  defp client_expiring_in(seconds) do
    Client.new(
      access_token: "test_token_abc",
      expires_at: DateTime.add(DateTime.utc_now(), seconds, :second)
    )
  end

  # ── expired?/1 ───────────────────────────────────────────────────────────────

  describe "expired?/1" do
    test "returns false when expires_at is nil" do
      client = Client.new(access_token: "tok")
      refute AuthToken.expired?(client)
    end

    test "returns false when expires_at is in the future" do
      client = client_expiring_in(3600)
      refute AuthToken.expired?(client)
    end

    test "returns true when expires_at is in the past" do
      client = client_expiring_in(-10)
      assert AuthToken.expired?(client)
    end
  end

  # ── seconds_until_expiry/1 ───────────────────────────────────────────────────

  describe "seconds_until_expiry/1" do
    test "returns nil when no expiry is set" do
      client = Client.new(access_token: "tok")
      assert is_nil(AuthToken.seconds_until_expiry(client))
    end

    test "returns positive seconds for future expiry" do
      client = client_expiring_in(500)
      secs = AuthToken.seconds_until_expiry(client)
      assert secs > 490 and secs <= 500
    end

    test "returns negative or zero for past expiry" do
      client = client_expiring_in(-60)
      assert AuthToken.seconds_until_expiry(client) <= 0
    end
  end

  # ── should_refresh?/2 ────────────────────────────────────────────────────────

  describe "should_refresh?/2" do
    test "returns false when no expiry is set" do
      client = Client.new(access_token: "tok")
      refute AuthToken.should_refresh?(client)
    end

    test "returns false when plenty of time remains" do
      client = client_expiring_in(3600)
      refute AuthToken.should_refresh?(client)
    end

    test "returns true when within default threshold (5 min)" do
      client = client_expiring_in(200)
      assert AuthToken.should_refresh?(client)
    end

    test "returns true when already expired" do
      client = client_expiring_in(-10)
      assert AuthToken.should_refresh?(client)
    end

    test "respects custom threshold_seconds option" do
      client = client_expiring_in(400)
      # Default threshold is 300s — not stale
      refute AuthToken.should_refresh?(client)
      # Custom threshold of 600s — now stale
      assert AuthToken.should_refresh?(client, threshold_seconds: 600)
    end
  end

  # ── expiry_summary/1 ─────────────────────────────────────────────────────────

  describe "expiry_summary/1" do
    test "returns 'no expiry' when expires_at is nil" do
      client = Client.new(access_token: "tok")
      assert AuthToken.expiry_summary(client) == "no expiry"
    end

    test "says 'expires in X min' for near expiry" do
      client = client_expiring_in(90)
      summary = AuthToken.expiry_summary(client)
      assert String.contains?(summary, "expires in")
      assert String.contains?(summary, "min")
    end

    test "says 'expires in Xh' for multi-hour expiry" do
      client = client_expiring_in(7200)
      summary = AuthToken.expiry_summary(client)
      assert String.contains?(summary, "expires in")
      assert String.contains?(summary, "h")
    end

    test "says 'expired X min ago' for past expiry" do
      client = client_expiring_in(-180)
      summary = AuthToken.expiry_summary(client)
      assert String.contains?(summary, "expired")
      assert String.contains?(summary, "min ago")
    end
  end

  # ── scopes/1 ─────────────────────────────────────────────────────────────────

  describe "scopes/1" do
    test "returns empty list when scope is nil" do
      client = Client.new(access_token: "tok", scope: nil)
      assert AuthToken.scopes(client) == []
    end

    test "returns empty list when scope is empty string" do
      client = client_with_scope("")
      assert AuthToken.scopes(client) == []
    end

    test "splits space-separated scopes" do
      client = client_with_scope("accounts:read transactions:read balances:read")
      assert AuthToken.scopes(client) == ["accounts:read", "transactions:read", "balances:read"]
    end

    test "splits comma-separated scopes" do
      client = client_with_scope("accounts:read,transactions:read")
      assert AuthToken.scopes(client) == ["accounts:read", "transactions:read"]
    end

    test "deduplicates scopes" do
      client = client_with_scope("accounts:read accounts:read transactions:read")
      assert AuthToken.scopes(client) == ["accounts:read", "transactions:read"]
    end
  end

  # ── has_scope?/2 ─────────────────────────────────────────────────────────────

  describe "has_scope?/2" do
    test "returns true when scope is present" do
      client = client_with_scope("accounts:read transactions:read")
      assert AuthToken.has_scope?(client, "accounts:read")
      assert AuthToken.has_scope?(client, "transactions:read")
    end

    test "returns false when scope is absent" do
      client = client_with_scope("accounts:read")
      refute AuthToken.has_scope?(client, "payment:write")
    end

    test "returns false when scope is nil" do
      client = Client.new(access_token: "tok", scope: nil)
      refute AuthToken.has_scope?(client, "accounts:read")
    end
  end

  # ── has_all_scopes?/2 ────────────────────────────────────────────────────────

  describe "has_all_scopes?/2" do
    test "returns true when all required scopes are present" do
      client = client_with_scope("accounts:read transactions:read balances:read")
      assert AuthToken.has_all_scopes?(client, ["accounts:read", "transactions:read"])
    end

    test "returns false when any required scope is missing" do
      client = client_with_scope("accounts:read")
      refute AuthToken.has_all_scopes?(client, ["accounts:read", "payment:write"])
    end

    test "returns true for empty required list" do
      client = Client.new(access_token: "tok", scope: nil)
      assert AuthToken.has_all_scopes?(client, [])
    end
  end

  # ── missing_scopes/2 ─────────────────────────────────────────────────────────

  describe "missing_scopes/2" do
    test "returns empty list when all scopes are present" do
      client = client_with_scope("accounts:read transactions:read")
      assert AuthToken.missing_scopes(client, ["accounts:read", "transactions:read"]) == []
    end

    test "returns missing scopes" do
      client = client_with_scope("accounts:read")

      missing =
        AuthToken.missing_scopes(client, ["accounts:read", "payment:write", "transactions:read"])

      assert Enum.sort(missing) == ["payment:write", "transactions:read"]
    end

    test "returns all scopes when token has no scope" do
      client = Client.new(access_token: "tok", scope: nil)
      assert AuthToken.missing_scopes(client, ["accounts:read"]) == ["accounts:read"]
    end
  end

  # ── summary/1 ────────────────────────────────────────────────────────────────

  describe "summary/1" do
    test "returns a map without the access token" do
      client = client_with_scope("accounts:read transactions:read")
      summary = AuthToken.summary(client)

      assert is_map(summary)
      refute Map.has_key?(summary, :access_token)
      assert summary.scope_count == 2
      assert "accounts:read" in summary.scopes
      assert is_boolean(summary.expired)
      assert is_binary(summary.expiry)
      assert is_boolean(summary.auto_refresh)
      assert is_boolean(summary.cache)
    end

    test "marks expired tokens correctly" do
      client = client_expiring_in(-10)
      summary = AuthToken.summary(client)
      assert summary.expired == true
    end
  end
end
