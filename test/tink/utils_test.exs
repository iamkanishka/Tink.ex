defmodule Tink.UtilsTest do
  use ExUnit.Case, async: true

  alias Tink.{Client, Utils}

  describe "put_if_present/3" do
    test "adds key when value is not nil" do
      assert Utils.put_if_present(%{}, "key", "val") == %{"key" => "val"}
    end

    test "skips key when value is nil" do
      assert Utils.put_if_present(%{}, "key", nil) == %{}
    end
  end

  describe "put_list_if_present/3" do
    test "joins list as comma string" do
      assert Utils.put_list_if_present(%{}, "ids", ["a", "b"]) == %{"ids" => "a,b"}
    end

    test "skips when nil" do
      assert Utils.put_list_if_present(%{}, "ids", nil) == %{}
    end
  end

  describe "pagination_params/1" do
    test "builds page params from opts" do
      result = Utils.pagination_params(page_token: "tok", page_size: 50)
      assert result == %{"pageToken" => "tok", "pageSize" => 50}
    end

    test "omits nil values" do
      result = Utils.pagination_params(page_size: 20)
      assert result == %{"pageSize" => 20}
      refute Map.has_key?(result, "pageToken")
    end
  end

  describe "token_prefix/1" do
    test "returns first 12 chars of access token" do
      client = %Client{access_token: "abcdefghijklmnop"}
      assert Utils.token_prefix(client) == "abcdefghijkl"
    end

    test "returns full token if shorter than 12 chars" do
      client = %Client{access_token: "short"}
      assert Utils.token_prefix(client) == "short"
    end
  end

  describe "params_hash/1" do
    test "returns a stable string for the same input" do
      assert Utils.params_hash(%{"a" => 1}) == Utils.params_hash(%{"a" => 1})
    end

    test "returns different hash for different inputs" do
      refute Utils.params_hash(%{"a" => 1}) == Utils.params_hash(%{"a" => 2})
    end
  end

  describe "poll_until/3" do
    test "returns {:ok, resp} on done status" do
      result =
        Utils.poll_until(
          fn -> {:ok, %{"status" => "COMPLETED"}} end,
          ["COMPLETED"]
        )

      assert {:ok, %{"status" => "COMPLETED"}} = result
    end

    test "returns {:error, :timeout} when deadline exceeded" do
      result =
        Utils.poll_until(
          fn -> {:ok, %{"status" => "PENDING"}} end,
          ["COMPLETED"],
          timeout_ms: 50,
          interval_ms: 10
        )

      assert {:error, :timeout} = result
    end

    test "returns {:error, %Tink.Error{}} on failed status" do
      result =
        Utils.poll_until(
          fn -> {:ok, %{"status" => "FAILED"}} end,
          ["COMPLETED"],
          timeout_ms: 1_000,
          interval_ms: 10
        )

      assert {:error, %Tink.Error{status: 422}} = result
    end

    test "propagates fetch errors immediately" do
      error = %Tink.Error{status: 500, message: "server error"}

      result =
        Utils.poll_until(
          fn -> {:error, error} end,
          ["COMPLETED"]
        )

      assert {:error, ^error} = result
    end
  end
end
