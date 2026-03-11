import Config

# =============================================================================
# Runtime Configuration
# =============================================================================
# This file is executed during runtime (not compile time) and is used to
# configure sensitive data from environment variables.
#
# It is loaded AFTER config/prod.exs and can override compile-time settings.

# Only configure in production or staging environments
if config_env() in [:prod, :staging] do
  # ==========================================================================
  # Tink API Credentials (REQUIRED)
  # ==========================================================================
  
  client_id =
    System.get_env("TINK_CLIENT_ID") ||
      raise """
      Environment variable TINK_CLIENT_ID is missing.
      You can get your Client ID from Tink Console: https://console.tink.com
      """

  client_secret =
    System.get_env("TINK_CLIENT_SECRET") ||
      raise """
      Environment variable TINK_CLIENT_SECRET is missing.
      You can get your Client Secret from Tink Console: https://console.tink.com
      """

  config :tink_ex,
    client_id: client_id,
    client_secret: client_secret

  # ==========================================================================
  # Optional: Custom API URL
  # ==========================================================================
  
  if api_url = System.get_env("TINK_API_URL") do
    config :tink_ex, base_url: api_url
  end

  # ==========================================================================
  # Optional: Actor Client ID (for delegation flows)
  # ==========================================================================
  
  if actor_client_id = System.get_env("TINK_ACTOR_CLIENT_ID") do
    config :tink_ex, actor_client_id: actor_client_id
  end

  # ==========================================================================
  # HTTP Configuration from Environment
  # ==========================================================================
  
  # HTTP Timeout (optional)
  if timeout = System.get_env("TINK_TIMEOUT") do
    config :tink_ex, timeout: String.to_integer(timeout)
  end

  # HTTP Pool Size (optional)
  if pool_size = System.get_env("TINK_POOL_SIZE") do
    config :tink_ex, TinkEx.Finch,
      pools: %{
        default: [size: String.to_integer(pool_size)]
      }
  end

  # ==========================================================================
  # Cache Configuration from Environment
  # ==========================================================================
  
  # Enable/Disable Cache
  cache_enabled =
    case System.get_env("TINK_CACHE_ENABLED", "true") do
      "true" -> true
      "false" -> false
      _ -> true
    end

  # Cache TTL (in seconds)
  cache_ttl =
    case System.get_env("TINK_CACHE_TTL") do
      nil -> :timer.minutes(5)
      value -> String.to_integer(value) * 1000
    end

  # Cache Size
  cache_size =
    case System.get_env("TINK_CACHE_SIZE") do
      nil -> 5000
      value -> String.to_integer(value)
    end

  config :tink_ex, :cache,
    enabled: cache_enabled,
    default_ttl: cache_ttl,
    max_size: cache_size

  # ==========================================================================
  # Rate Limiting from Environment
  # ==========================================================================
  
  rate_limit_enabled =
    case System.get_env("TINK_RATE_LIMIT_ENABLED", "true") do
      "true" -> true
      "false" -> false
      _ -> true
    end

  rate_limit_max =
    case System.get_env("TINK_RATE_LIMIT_MAX") do
      nil -> 100
      value -> String.to_integer(value)
    end

  config :tink_ex, :rate_limit,
    enabled: rate_limit_enabled,
    max_requests: rate_limit_max

  # ==========================================================================
  # JWT/Joken Configuration from Environment
  # ==========================================================================
  
  if jwt_secret = System.get_env("JWT_SECRET") do
    config :joken,
      default_signer: [
        signer_alg: System.get_env("JWT_ALGORITHM", "HS256"),
        key_pem: jwt_secret
      ]
  end

  # ==========================================================================
  # Database Configuration (if using Ecto)
  # ==========================================================================
  
  # Uncomment if using database
  # database_url =
  #   System.get_env("DATABASE_URL") ||
  #     raise """
  #     Environment variable DATABASE_URL is missing.
  #     For example: ecto://USER:PASS@HOST/DATABASE
  #     """

  # maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # config :tink_ex, TinkEx.Repo,
  #   url: database_url,
  #   pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  #   socket_options: maybe_ipv6

  # ==========================================================================
  # Error Tracking Configuration
  # ==========================================================================
  
  # Sentry
  if sentry_dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: config_env(),
      enable_source_code_context: true,
      root_source_code_path: File.cwd!()
  end

  # AppSignal
  if appsignal_key = System.get_env("APPSIGNAL_PUSH_API_KEY") do
    config :appsignal, :config,
      active: true,
      name: "TinkEx",
      push_api_key: appsignal_key,
      env: config_env()
  end

  # ==========================================================================
  # Logging Level from Environment
  # ==========================================================================
  
  log_level =
    case System.get_env("LOG_LEVEL", "info") do
      "debug" -> :debug
      "info" -> :info
      "warning" -> :warning
      "warn" -> :warning
      "error" -> :error
      _ -> :info
    end

  config :logger, level: log_level

  # ==========================================================================
  # Debug Mode (for troubleshooting production issues)
  # ==========================================================================
  
  debug_mode =
    case System.get_env("TINK_DEBUG", "false") do
      "true" -> true
      "1" -> true
      _ -> false
    end

  config :tink_ex, debug_mode: debug_mode
end

# =============================================================================
# Development Runtime Configuration
# =============================================================================

if config_env() == :dev do
  # Load .env file in development (if using dotenv)
  # You can use libraries like `dotenvy` for this
  
  # Example: Override with env vars if present
  if client_id = System.get_env("TINK_CLIENT_ID") do
    config :tink_ex, client_id: client_id
  end

  if client_secret = System.get_env("TINK_CLIENT_SECRET") do
    config :tink_ex, client_secret: client_secret
  end
end

# =============================================================================
# Staging Environment (if needed)
# =============================================================================

if config_env() == :staging do
  # Staging uses production-like settings but with test API
  config :tink_ex,
    base_url: System.get_env("TINK_API_URL", "https://api.tink.com")

  # Enable more verbose logging in staging
  config :logger, level: :debug

  # Use smaller cache in staging
  config :tink_ex, :cache,
    enabled: true,
    max_size: 1000
end
