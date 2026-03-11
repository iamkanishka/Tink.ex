defmodule TinkEx.Config do
  @moduledoc """
  Configuration management for TinkEx.

  This module handles loading and validating configuration from multiple sources:

  1. Application environment (config.exs)
  2. System environment variables
  3. Runtime options

  ## Configuration Options

  ### Required
  - `:client_id` - Tink OAuth client ID
  - `:client_secret` - Tink OAuth client secret (for client credentials flow)

  ### Optional
  - `:environment` - `:production` or `:sandbox` (default: :production)
  - `:base_url` - API base URL (default: based on environment)
  - `:timeout` - Request timeout in ms (default: 30_000)
  - `:max_retries` - Maximum retry attempts (default: 3)
  - `:pool_size` - HTTP connection pool size (default: 32)
  - `:enable_caching` - Enable token caching (default: true)
  - `:enable_rate_limiting` - Enable rate limiting (default: true)
  - `:http_client` - HTTP client module (default: TinkEx.HTTPAdapter)
  - `:debug_mode` - Enable debug logging (default: false)

  ## Configuration Sources

  ### Application Config

      # config/config.exs
      config :tink_ex,
        client_id: "your_client_id",
        client_secret: "your_client_secret",
        environment: :production

  ### System Environment Variables

      export TINK_CLIENT_ID="your_client_id"
      export TINK_CLIENT_SECRET="your_client_secret"
      export TINK_ENVIRONMENT="production"

  ### Runtime Options

      client = TinkEx.client(
        client_id: "runtime_id",
        client_secret: "runtime_secret"
      )

  ## Precedence

  Runtime options > Environment variables > Application config > Defaults
  """

  @production_url "https://api.tink.com"
  @sandbox_url "https://api.tink.com"  # Tink uses same URL, different credentials

  @default_config %{
    environment: :production,
    timeout: 30_000,
    max_retries: 3,
    pool_size: 32,
    pool_timeout: 5_000,
    enable_caching: true,
    enable_rate_limiting: true,
    http_client: TinkEx.HTTPAdapter,
    debug_mode: false
  }

  @doc """
  Gets a configuration value.

  Checks in order:
  1. Application environment
  2. System environment variable
  3. Default value (if provided)

  ## Examples

      iex> TinkEx.Config.get(:client_id)
      "your_client_id"

      iex> TinkEx.Config.get(:timeout, 5000)
      30000
  """
  @spec get(atom(), term()) :: term()
  def get(key, default \\ nil) do
    Application.get_env(:tink_ex, key) ||
      get_from_env(key) ||
      Map.get(@default_config, key, default)
  end

  @doc """
  Gets all configuration as a keyword list.

  ## Examples

      iex> TinkEx.Config.get_all()
      [
        client_id: "your_id",
        client_secret: "your_secret",
        environment: :production,
        ...
      ]
  """
  @spec get_all() :: keyword()
  def get_all do
    app_config = Application.get_all_env(:tink_ex)
    env_config = get_all_from_env()

    @default_config
    |> Map.merge(Map.new(app_config))
    |> Map.merge(env_config)
    |> Map.to_list()
  end

  @doc """
  Validates the current configuration.

  Returns `:ok` if valid, `{:error, reason}` if invalid.

  ## Examples

      iex> TinkEx.Config.validate()
      :ok

      iex> TinkEx.Config.validate()
      {:error, "Missing required configuration: client_id"}
  """
  @spec validate() :: :ok | {:error, String.t()}
  def validate do
    config = get_all()

    cond do
      missing_required?(config) ->
        {:error, "Missing required configuration: #{missing_keys(config)}"}

      invalid_environment?(config) ->
        {:error, "Invalid environment. Must be :production or :sandbox"}

      invalid_url?(config) ->
        {:error, "Invalid base_url configuration"}

      true ->
        :ok
    end
  end

  @doc """
  Builds client configuration from options.

  Merges provided options with application configuration.

  ## Examples

      iex> TinkEx.Config.build_client_config(client_id: "custom_id")
      %{client_id: "custom_id", client_secret: "...", ...}
  """
  @spec build_client_config(keyword()) :: map()
  def build_client_config(opts \\ []) do
    base_config = get_all() |> Map.new()
    opts_map = Map.new(opts)

    config =
      base_config
      |> Map.merge(opts_map)
      |> resolve_base_url()

    config
  end

  @doc """
  Gets the base URL for the configured environment.

  ## Examples

      iex> TinkEx.Config.base_url()
      "https://api.tink.com"
  """
  @spec base_url() :: String.t()
  def base_url do
    case get(:base_url) do
      nil ->
        case get(:environment, :production) do
          :production -> @production_url
          :sandbox -> @sandbox_url
          _ -> @production_url
        end

      url when is_binary(url) ->
        url
    end
  end

  @doc """
  Checks if caching is enabled.

  ## Examples

      iex> TinkEx.Config.caching_enabled?()
      true
  """
  @spec caching_enabled?() :: boolean()
  def caching_enabled? do
    get(:enable_caching, true)
  end

  @doc """
  Checks if rate limiting is enabled.
  """
  @spec rate_limiting_enabled?() :: boolean()
  def rate_limiting_enabled? do
    get(:enable_rate_limiting, true)
  end

  @doc """
  Checks if debug mode is enabled.
  """
  @spec debug_mode?() :: boolean()
  def debug_mode? do
    get(:debug_mode, false)
  end

  # Private Functions

  defp get_from_env(:client_id), do: System.get_env("TINK_CLIENT_ID")
  defp get_from_env(:client_secret), do: System.get_env("TINK_CLIENT_SECRET")
  defp get_from_env(:base_url), do: System.get_env("TINK_BASE_URL")

  defp get_from_env(:environment) do
    case System.get_env("TINK_ENVIRONMENT") do
      "production" -> :production
      "sandbox" -> :sandbox
      _ -> nil
    end
  end

  defp get_from_env(:timeout) do
    case System.get_env("TINK_TIMEOUT") do
      nil -> nil
      value -> String.to_integer(value)
    end
  end

  defp get_from_env(:max_retries) do
    case System.get_env("TINK_MAX_RETRIES") do
      nil -> nil
      value -> String.to_integer(value)
    end
  end

  defp get_from_env(:enable_caching) do
    case System.get_env("TINK_ENABLE_CACHING") do
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp get_from_env(:enable_rate_limiting) do
    case System.get_env("TINK_ENABLE_RATE_LIMITING") do
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp get_from_env(:debug_mode) do
    case System.get_env("TINK_DEBUG_MODE") do
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp get_from_env(_), do: nil

  defp get_all_from_env do
    %{
      client_id: get_from_env(:client_id),
      client_secret: get_from_env(:client_secret),
      base_url: get_from_env(:base_url),
      environment: get_from_env(:environment),
      timeout: get_from_env(:timeout),
      max_retries: get_from_env(:max_retries),
      enable_caching: get_from_env(:enable_caching),
      enable_rate_limiting: get_from_env(:enable_rate_limiting),
      debug_mode: get_from_env(:debug_mode)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp missing_required?(config) do
    # Access token OR (client_id AND client_secret) required
    access_token = Keyword.get(config, :access_token)
    client_id = Keyword.get(config, :client_id)
    client_secret = Keyword.get(config, :client_secret)

    is_nil(access_token) and (is_nil(client_id) or is_nil(client_secret))
  end

  defp missing_keys(config) do
    required = [:client_id, :client_secret]

    required
    |> Enum.reject(fn key -> Keyword.has_key?(config, key) end)
    |> Enum.join(", ")
  end

  defp invalid_environment?(config) do
    env = Keyword.get(config, :environment)
    env not in [:production, :sandbox, nil]
  end

  defp invalid_url?(config) do
    case Keyword.get(config, :base_url) do
      nil -> false
      url when is_binary(url) -> not String.starts_with?(url, "http")
      _ -> true
    end
  end

  defp resolve_base_url(%{base_url: url} = config) when is_binary(url) do
    config
  end

  defp resolve_base_url(%{environment: :sandbox} = config) do
    Map.put(config, :base_url, @sandbox_url)
  end

  defp resolve_base_url(%{environment: :production} = config) do
    Map.put(config, :base_url, @production_url)
  end

  defp resolve_base_url(config) do
    Map.put(config, :base_url, @production_url)
  end
end
