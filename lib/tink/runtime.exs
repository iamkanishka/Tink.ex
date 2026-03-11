import Config

# Runtime configuration - loaded at application startup
# This file is loaded after the application has been compiled
# Perfect for configuration from environment variables

if config_env() == :prod do
  # Tink API Credentials (REQUIRED in production)
  client_id =
    System.get_env("TINK_CLIENT_ID") ||
      raise """
      environment variable TINK_CLIENT_ID is missing.
      You can set it in your production environment or pass it when starting the application:

        TINK_CLIENT_ID=your_client_id mix phx.server
      """

  client_secret =
    System.get_env("TINK_CLIENT_SECRET") ||
      raise """
      environment variable TINK_CLIENT_SECRET is missing.
      You can set it in your production environment or pass it when starting the application:

        TINK_CLIENT_SECRET=your_secret mix phx.server
      """

  config :tink,
    client_id: client_id,
    client_secret: client_secret

  # Optional: Override API base URL
  if api_url = System.get_env("TINK_API_URL") do
    config :tink, api_base_url: api_url
  end

  # Optional: Override redirect URI
  if redirect_uri = System.get_env("TINK_REDIRECT_URI") do
    config :tink, redirect_uri: redirect_uri
  end

  # Optional: Actor client ID for delegated access
  if actor_client_id = System.get_env("TINK_ACTOR_CLIENT_ID") do
    config :tink, actor_client_id: actor_client_id
  end

  # HTTP Configuration from environment
  timeout =
    System.get_env("TINK_TIMEOUT", "30000")
    |> String.to_integer()

  max_retries =
    System.get_env("TINK_MAX_RETRIES", "3")
    |> String.to_integer()

  config :tink,
    timeout: timeout,
    max_retries: max_retries

  # Cache Configuration from environment
  cache_enabled =
    System.get_env("TINK_CACHE_ENABLED", "true")
    |> String.downcase()
    |> case do
      "true" -> true
      "1" -> true
      "yes" -> true
      _ -> false
    end

  cache_ttl =
    System.get_env("TINK_CACHE_TTL")
    |> case do
      nil -> :timer.minutes(5)
      ttl -> String.to_integer(ttl)
    end

  cache_max_size =
    System.get_env("TINK_CACHE_MAX_SIZE", "5000")
    |> String.to_integer()

  config :tink, :cache,
    enabled: cache_enabled,
    default_ttl: cache_ttl,
    max_size: cache_max_size

  # Rate Limiting Configuration from environment
  rate_limit_enabled =
    System.get_env("TINK_RATE_LIMIT_ENABLED", "true")
    |> String.downcase()
    |> case do
      "true" -> true
      "1" -> true
      "yes" -> true
      _ -> false
    end

  rate_limit_rps =
    System.get_env("TINK_RATE_LIMIT_RPS", "10")
    |> String.to_integer()

  rate_limit_burst =
    System.get_env("TINK_RATE_LIMIT_BURST", "20")
    |> String.to_integer()

  config :tink, :rate_limit,
    enabled: rate_limit_enabled,
    requests_per_second: rate_limit_rps,
    burst_size: rate_limit_burst

  # Finch Pool Configuration from environment
  pool_size =
    System.get_env("TINK_POOL_SIZE", "100")
    |> String.to_integer()

  pool_count =
    System.get_env("TINK_POOL_COUNT", "4")
    |> String.to_integer()

  config :tink, Tink.Finch,
    pools: %{
      default: [
        size: pool_size,
        count: pool_count,
        conn_opts: [
          transport_opts: [
            timeout: timeout,
            keepalive: true
          ]
        ]
      ]
    }

  # Logging Configuration from environment
  log_level =
    System.get_env("TINK_LOG_LEVEL", "info")
    |> String.to_existing_atom()

  config :logger, level: log_level

  # Telemetry Configuration from environment
  telemetry_enabled =
    System.get_env("TINK_TELEMETRY_ENABLED", "true")
    |> String.downcase()
    |> case do
      "true" -> true
      "1" -> true
      "yes" -> true
      _ -> false
    end

  config :tink, :telemetry,
    enabled: telemetry_enabled,
    log_level: log_level

  # Optional: APM/Monitoring Integration
  if honeybadger_api_key = System.get_env("HONEYBADGER_API_KEY") do
    config :honeybadger,
      api_key: honeybadger_api_key,
      environment_name: :prod
  end

  if sentry_dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: :prod,
      enable_source_code_context: true,
      root_source_code_path: File.cwd!(),
      tags: %{
        env: "production"
      }
  end
end

# Development/Test runtime configuration
if config_env() in [:dev, :test] do
  # Allow overriding credentials in dev/test
  if client_id = System.get_env("TINK_CLIENT_ID") do
    config :tink, client_id: client_id
  end

  if client_secret = System.get_env("TINK_CLIENT_SECRET") do
    config :tink, client_secret: client_secret
  end

  if api_url = System.get_env("TINK_API_URL") do
    config :tink, api_base_url: api_url
  end

  # Development cache override
  if cache_enabled = System.get_env("TINK_CACHE_ENABLED") do
    enabled =
      cache_enabled
      |> String.downcase()
      |> case do
        "true" -> true
        "1" -> true
        "yes" -> true
        _ -> false
      end

    config :tink, :cache, enabled: enabled
  end
end
