defmodule Tink.Config do
  @moduledoc """
  Runtime configuration for the Tink SDK.

  Set values in `config/runtime.exs`:

      config :tink,
        client_id:      System.get_env("TINK_CLIENT_ID"),
        client_secret:  System.get_env("TINK_CLIENT_SECRET"),
        base_url:       "https://api.tink.com",
        link_base_url:  "https://link.tink.com",
        webhook_secret: System.get_env("TINK_WEBHOOK_SECRET"),
        timeout:        30_000,
        max_retries:    3,
        retry_delay:    500,
        http_adapter:   Tink.HTTP.Finch,
        cache: [
          enabled:  true,
          max_size: 1_000
        ]

  ## Disabling cache in tests

      # config/test.exs
      config :tink, cache: [enabled: false]

  """

  @base_url "https://api.tink.com"
  @link_base_url "https://link.tink.com"
  @timeout 30_000
  @max_retries 3
  @retry_delay 500

  @spec client_id() :: String.t()
  def client_id, do: get!(:client_id)

  @spec client_secret() :: String.t()
  def client_secret, do: get!(:client_secret)

  @spec base_url() :: String.t()
  def base_url, do: get(:base_url, @base_url)

  @spec link_base_url() :: String.t()
  def link_base_url, do: get(:link_base_url, @link_base_url)

  @spec webhook_secret() :: String.t() | nil
  def webhook_secret, do: get(:webhook_secret, nil)

  @spec timeout() :: pos_integer()
  def timeout, do: get(:timeout, @timeout)

  @spec max_retries() :: non_neg_integer()
  def max_retries, do: get(:max_retries, @max_retries)

  @spec retry_delay() :: non_neg_integer()
  def retry_delay, do: get(:retry_delay, @retry_delay)

  @spec http_adapter() :: module()
  def http_adapter, do: get(:http_adapter, Tink.HTTP.Finch)

  @spec cache_enabled?() :: boolean()
  def cache_enabled? do
    cache_cfg = get(:cache, [])
    Keyword.get(cache_cfg, :enabled, true)
  end

  @spec cache_max_size() :: pos_integer()
  def cache_max_size do
    cache_cfg = get(:cache, [])
    Keyword.get(cache_cfg, :max_size, 1_000)
  end

  @spec rate_limit_cfg() :: keyword()
  def rate_limit_cfg, do: get(:rate_limit, [])

  defp get(key, default), do: Application.get_env(:tink, key, default)

  defp get!(key) do
    case Application.get_env(:tink, key) do
      nil -> raise ArgumentError, "Tink config missing: #{inspect(key)}"
      val -> val
    end
  end
end
