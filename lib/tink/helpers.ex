defmodule Tink.Helpers do
  @moduledoc """
  Helper functions and utilities for Tink.

  Provides common utility functions used throughout the library:

  - URL building and encoding
  - Query parameter handling
  - Response parsing
  - Date/time formatting
  - Money/decimal handling

  ## Examples

      # Build URL with query params
      url = Tink.Helpers.build_url("/api/v1/accounts", page_size: 10, page_token: "abc")
      #=> "/api/v1/accounts?page_size=10&page_token=abc"

      # Parse money amount
      amount = Tink.Helpers.parse_money(%{"value" => "123.45", "currencyCode" => "USD"})
      #=> %{amount: #Decimal<123.45>, currency: "USD"}
  """

  @doc """
  Builds a URL with query parameters.

  ## Examples

      iex> Tink.Helpers.build_url("/api/v1/accounts", page_size: 10)
      "/api/v1/accounts?page_size=10"

      iex> Tink.Helpers.build_url("/api/v1/accounts", [])
      "/api/v1/accounts"
  """
  @spec build_url(String.t(), keyword() | map()) :: String.t()
  def build_url(path, params) when is_list(params) or is_map(params) do
    case build_query_string(params) do
      "" -> path
      query_string -> "#{path}?#{query_string}"
    end
  end

  @doc """
  Builds a query string from parameters.

  Handles nil values, lists, and nested maps appropriately.

  ## Examples

      iex> Tink.Helpers.build_query_string(foo: "bar", baz: 123)
      "foo=bar&baz=123"

      iex> Tink.Helpers.build_query_string(foo: nil, bar: "baz")
      "bar=baz"
  """
  @spec build_query_string(keyword() | map()) :: String.t()
  def build_query_string(params) when is_list(params) or is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map_join("&", &encode_param/1)
  end

  @doc """
  Converts snake_case to camelCase.

  ## Examples

      iex> Tink.Helpers.to_camel_case("page_size")
      "pageSize"

      iex> Tink.Helpers.to_camel_case("page_token")
      "pageToken"
  """
  @spec to_camel_case(String.t() | atom()) :: String.t()
  def to_camel_case(key) when is_atom(key) do
    key |> Atom.to_string() |> to_camel_case()
  end

  def to_camel_case(key) when is_binary(key) do
    [first | rest] = String.split(key, "_")

    rest
    |> Enum.map(&String.capitalize/1)
    |> then(fn parts -> [first | parts] end)
    |> Enum.join("")
  end

  @doc """
  Parses a money amount from Tink API response.

  ## Examples

      iex> Tink.Helpers.parse_money(%{"value" => "123.45", "currencyCode" => "USD"})
      %{amount: Decimal.new("123.45"), currency: "USD"}

      iex> Tink.Helpers.parse_money(%{"value" => 123.45, "currencyCode" => "EUR"})
      %{amount: Decimal.new("123.45"), currency: "EUR"}
  """
  @spec parse_money(map()) :: %{amount: Decimal.t(), currency: String.t()} | nil
  def parse_money(%{"value" => value, "currencyCode" => currency})
      when not is_nil(value) do
    %{
      amount: parse_decimal(value),
      currency: currency
    }
  end

  def parse_money(_), do: nil

  @doc """
  Parses a decimal value safely.

  ## Examples

      iex> Tink.Helpers.parse_decimal("123.45")
      #Decimal<123.45>

      iex> Tink.Helpers.parse_decimal(123.45)
      #Decimal<123.45>

      iex> Tink.Helpers.parse_decimal(nil)
      #Decimal<0>
  """
  @spec parse_decimal(String.t() | number() | nil) :: Decimal.t()
  def parse_decimal(nil), do: Decimal.new(0)
  def parse_decimal(value) when is_binary(value), do: Decimal.new(value)
  def parse_decimal(value) when is_number(value), do: Decimal.from_float(value)

  @doc """
  Formats a date for the Tink API (ISO 8601).

  ## Examples

      iex> date = ~D[2024-01-15]
      iex> Tink.Helpers.format_date(date)
      "2024-01-15"

      iex> Tink.Helpers.format_date("2024-01-15")
      "2024-01-15"
  """
  @spec format_date(Date.t() | String.t()) :: String.t()
  def format_date(%Date{} = date), do: Date.to_iso8601(date)
  def format_date(date_string) when is_binary(date_string), do: date_string

  @doc """
  Parses a date from ISO 8601 string.

  ## Examples

      iex> Tink.Helpers.parse_date("2024-01-15")
      {:ok, ~D[2024-01-15]}

      iex> Tink.Helpers.parse_date("invalid")
      {:error, :invalid_date}
  """
  @spec parse_date(String.t()) :: {:ok, Date.t()} | {:error, atom()}
  def parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :invalid_date}
    end
  end

  @doc """
  Safely gets a nested value from a map.

  ## Examples

      iex> map = %{"user" => %{"name" => "John"}}
      iex> Tink.Helpers.get_in_safe(map, ["user", "name"])
      "John"

      iex> Tink.Helpers.get_in_safe(map, ["user", "age"])
      nil
  """
  @spec get_in_safe(map(), [String.t() | atom()]) :: term()
  def get_in_safe(map, keys) when is_map(map) and is_list(keys) do
    get_in(map, keys)
  rescue
    _ -> nil
  end

  @doc """
  Merges pagination params into options.

  ## Examples

      iex> Tink.Helpers.merge_pagination_params([page_size: 10], "token123")
      [page_size: 10, page_token: "token123"]
  """
  @spec merge_pagination_params(keyword(), String.t() | nil) :: keyword()
  def merge_pagination_params(opts, nil), do: opts

  def merge_pagination_params(opts, page_token) when is_binary(page_token) do
    Keyword.put(opts, :page_token, page_token)
  end

  @doc """
  Validates required parameters are present.

  ## Examples

      iex> params = %{user_id: "123", scope: "accounts:read"}
      iex> Tink.Helpers.validate_required(params, [:user_id, :scope])
      :ok

      iex> params = %{user_id: "123"}
      iex> Tink.Helpers.validate_required(params, [:user_id, :scope])
      {:error, "Missing required parameter: scope"}
  """
  @spec validate_required(map(), [atom()]) :: :ok | {:error, String.t()}
  def validate_required(params, required_keys) when is_map(params) do
    missing =
      required_keys
      |> Enum.reject(fn key -> Map.has_key?(params, key) end)

    case missing do
      [] ->
        :ok

      [key | _] ->
        {:error, "Missing required parameter: #{key}"}
    end
  end

  @doc """
  Safely encodes body as JSON.

  ## Examples

      iex> Tink.Helpers.encode_json(%{foo: "bar"})
      {:ok, ~s({"foo":"bar"})}

      iex> Tink.Helpers.encode_json(nil)
      {:ok, nil}
  """
  @spec encode_json(term()) :: {:ok, String.t() | nil} | {:error, term()}
  def encode_json(nil), do: {:ok, nil}

  def encode_json(data) do
    Jason.encode(data)
  end

  @doc """
  Safely decodes JSON.

  ## Examples

      iex> Tink.Helpers.decode_json(~s({"foo":"bar"}))
      {:ok, %{"foo" => "bar"}}

      iex> Tink.Helpers.decode_json("invalid")
      {:error, %Jason.DecodeError{}}
  """
  @spec decode_json(String.t()) :: {:ok, term()} | {:error, Jason.DecodeError.t()}
  def decode_json(json) when is_binary(json) do
    Jason.decode(json)
  end

  @doc """
  Redacts sensitive information from logs.

  ## Examples

      iex> Tink.Helpers.redact_sensitive(%{access_token: "secret", data: "public"})
      %{access_token: "[REDACTED]", data: "public"}
  """
  @spec redact_sensitive(map()) :: map()
  def redact_sensitive(data) when is_map(data) do
    sensitive_keys = [
      "access_token",
      "accessToken",
      "refresh_token",
      "refreshToken",
      "client_secret",
      "clientSecret",
      "password",
      "api_key",
      "apiKey"
    ]

    Enum.reduce(sensitive_keys, data, fn key, acc ->
      if Map.has_key?(acc, key) do
        Map.put(acc, key, "[REDACTED]")
      else
        acc
      end
    end)
  end

  # Private Functions

  defp encode_param({key, value}) when is_list(value) do
    # Handle list values (e.g., account_ids)
    camel_key = to_camel_case(key)
    Enum.map_join(value, "&", fn v -> "#{camel_key}=#{URI.encode_www_form(to_string(v))}" end)
  end

  defp encode_param({key, value}) do
    camel_key = to_camel_case(key)
    "#{camel_key}=#{URI.encode_www_form(to_string(value))}"
  end
end
