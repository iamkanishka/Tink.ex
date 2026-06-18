defmodule Tink.ErrorTest do
  use ExUnit.Case, async: true

  describe "from_response/3" do
    test "extracts errorCode and errorMessage" do
      body = %{"errorCode" => "NOT_FOUND", "errorMessage" => "Resource not found"}
      err = Tink.Error.from_response(404, body, "req-abc")
      assert err.status == 404
      assert err.code == "NOT_FOUND"
      assert err.message == "Resource not found"
      assert err.request_id == "req-abc"
      assert err.details == body
    end

    test "falls back to 'error' key" do
      err = Tink.Error.from_response(400, %{"error" => "invalid_grant"})
      assert err.code == "invalid_grant"
    end

    test "falls back to 'error_description'" do
      err = Tink.Error.from_response(400, %{"error" => "x", "error_description" => "Token expired"})
      assert err.message == "Token expired"
    end

    test "works without request_id" do
      err = Tink.Error.from_response(500, %{"errorMessage" => "oops"})
      assert is_nil(err.request_id)
    end

    test "handles empty body gracefully" do
      err = Tink.Error.from_response(503, %{})
      assert err.status == 503
      assert err.message == "Unknown error"
    end
  end

  describe "network/1" do
    test "builds a network error with nil status" do
      err = Tink.Error.network("connection refused")
      assert is_nil(err.status)
      assert err.code == "NETWORK_ERROR"
      assert err.message == "connection refused"
    end
  end

  describe "decode/1" do
    test "builds a decode error" do
      err = Tink.Error.decode("unexpected byte")
      assert err.code == "DECODE_ERROR"
    end
  end

  describe "Exception.message/1" do
    test "formats error with status and code" do
      err = %Tink.Error{status: 401, code: "UNAUTHENTICATED", message: "Token expired"}
      assert Exception.message(err) == "[401] UNAUTHENTICATED: Token expired"
    end

    test "handles nil status gracefully" do
      err = %Tink.Error{status: nil, code: "NETWORK_ERROR", message: "timeout"}
      assert Exception.message(err) == "[?] NETWORK_ERROR: timeout"
    end
  end

  describe "raise/1" do
    test "can be raised as an exception" do
      err =
        Tink.Error.from_response(422, %{"errorCode" => "INVALID", "errorMessage" => "bad input"})

      assert_raise Tink.Error, "[422] INVALID: bad input", fn -> raise err end
    end
  end
end

defmodule Tink.PaginatorTest do
  use ExUnit.Case, async: true

  describe "stream/2" do
    test "yields all items across multiple pages" do
      pages = [
        %{"items" => [1, 2, 3], "nextPageToken" => "p2"},
        %{"items" => [4, 5], "nextPageToken" => "p3"},
        %{"items" => [6], "nextPageToken" => nil}
      ]

      fetch_fn = fn
        nil -> {:ok, Enum.at(pages, 0)}
        "p2" -> {:ok, Enum.at(pages, 1)}
        "p3" -> {:ok, Enum.at(pages, 2)}
      end

      assert Tink.Paginator.stream(fetch_fn) |> Enum.to_list() == [1, 2, 3, 4, 5, 6]
    end

    test "stops immediately on first fetch error" do
      fetch_fn = fn _token -> {:error, %Tink.Error{status: 500, message: "error"}} end
      assert Tink.Paginator.stream(fetch_fn) |> Enum.to_list() == []
    end

    test "stops when nextPageToken is empty string" do
      fetch_fn = fn _token ->
        {:ok, %{"items" => ["a", "b"], "nextPageToken" => ""}}
      end

      assert Tink.Paginator.stream(fetch_fn) |> Enum.to_list() == ["a", "b"]
    end

    test "respects custom items_key" do
      fetch_fn = fn _token ->
        {:ok, %{"transactions" => ["tx1", "tx2"], "nextPageToken" => nil}}
      end

      result = Tink.Paginator.stream(fetch_fn, items_key: "transactions") |> Enum.to_list()
      assert result == ["tx1", "tx2"]
    end

    test "respects custom token_key" do
      fetch_fn = fn
        nil -> {:ok, %{"items" => [1], "cursor" => "next"}}
        "next" -> {:ok, %{"items" => [2], "cursor" => nil}}
      end

      result = Tink.Paginator.stream(fetch_fn, token_key: "cursor") |> Enum.to_list()
      assert result == [1, 2]
    end

    test "handles missing items key gracefully" do
      fetch_fn = fn _token -> {:ok, %{"nextPageToken" => nil}} end
      assert Tink.Paginator.stream(fetch_fn) |> Enum.to_list() == []
    end

    test "is lazy — does not fetch beyond what is consumed" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn _token ->
        :counters.add(call_count, 1, 1)
        {:ok, %{"items" => [1, 2, 3], "nextPageToken" => "more"}}
      end

      # Take only 2 — should only fetch the first page
      Tink.Paginator.stream(fetch_fn) |> Enum.take(2)
      assert :counters.get(call_count, 1) == 1
    end
  end

  describe "collect_all/2" do
    test "collects all items across all pages" do
      fetch_fn = fn
        nil -> {:ok, %{"items" => ["a", "b"], "nextPageToken" => "p2"}}
        "p2" -> {:ok, %{"items" => ["c"], "nextPageToken" => nil}}
      end

      assert {:ok, ["a", "b", "c"]} = Tink.Paginator.collect_all(fetch_fn)
    end

    test "returns error on first fetch failure" do
      err = %Tink.Error{status: 500, message: "Server error"}
      fetch_fn = fn _token -> {:error, err} end
      assert {:error, ^err} = Tink.Paginator.collect_all(fetch_fn)
    end

    test "returns empty list when first page has no items" do
      fetch_fn = fn _token -> {:ok, %{"items" => [], "nextPageToken" => nil}} end
      assert {:ok, []} = Tink.Paginator.collect_all(fetch_fn)
    end

    test "respects items_key override" do
      fetch_fn = fn _token ->
        {:ok, %{"accounts" => [%{"id" => "a1"}], "nextPageToken" => nil}}
      end

      assert {:ok, [%{"id" => "a1"}]} = Tink.Paginator.collect_all(fetch_fn, items_key: "accounts")
    end
  end
end

defmodule Tink.ErrorHelperTest do
  use ExUnit.Case, async: true

  alias Tink.Error

  describe "retryable?/1" do
    test "true for 429" do
      assert Error.retryable?(%Error{status: 429, message: "rate limited"})
    end

    test "true for 503" do
      assert Error.retryable?(%Error{status: 503, message: "unavailable"})
    end

    test "true for nil status (network error)" do
      assert Error.retryable?(%Error{status: nil, message: "timeout"})
    end

    test "false for 400, 401, 403, 404, 422" do
      for status <- [400, 401, 403, 404, 422] do
        refute Error.retryable?(%Error{status: status, message: "x"})
      end
    end
  end

  describe "auth_error?/1" do
    test "true for 401 and 403" do
      assert Error.auth_error?(%Error{status: 401, message: "x"})
      assert Error.auth_error?(%Error{status: 403, message: "x"})
    end

    test "false for other statuses" do
      refute Error.auth_error?(%Error{status: 404, message: "x"})
      refute Error.auth_error?(%Error{status: 500, message: "x"})
      refute Error.auth_error?(%Error{status: nil, message: "x"})
    end
  end

  describe "not_found?/1" do
    test "true for 404" do
      assert Error.not_found?(%Error{status: 404, message: "x"})
    end

    test "false for other statuses" do
      refute Error.not_found?(%Error{status: 400, message: "x"})
      refute Error.not_found?(%Error{status: nil, message: "x"})
    end
  end
end
