defmodule Tink.RateLimiterTest do
  use ExUnit.Case, async: true

  # Rate limiter is disabled in test config — all checks return :ok
  describe "check/1 (rate limiting disabled in test env)" do
    test "returns :ok when rate limiting is disabled" do
      assert :ok = Tink.RateLimiter.check("test-client-id")
    end
  end

  describe "enabled?/0" do
    test "returns false in test environment" do
      # config/test.exs sets rate_limit: [enabled: false]
      refute Tink.RateLimiter.enabled?()
    end
  end

  describe "requests_per_minute/0 and burst_size/0" do
    test "return positive integers" do
      # These read from config with defaults — just assert they're sensible
      assert Tink.RateLimiter.requests_per_minute() > 0
      assert Tink.RateLimiter.burst_size() > 0
    end
  end
end
