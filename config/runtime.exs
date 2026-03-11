import Config

# =============================================================================
# Runtime Configuration
# =============================================================================
# Executed at runtime (not compile time). Loaded AFTER prod.exs.
# All sensitive credentials and environment-specific overrides live here.

if config_env() == :prod do
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

  config :tink,
    client_id: client_id,
    client_secret: client_secret

  # ==========================================================================
  # Optional: Custom API URL
  # ==========================================================================

  if api_url = System.get_env("TINK_API_URL") do
    config :tink, base_url: api_url
  end

  # ==========================================================================
  # Optional: Actor Client ID (for delegation flows)
  # ==========================================================================

  if actor_client_id = System.get_env("TINK_ACTOR_CLIENT_ID") do
    config :tink, actor_client_id: actor_client_id
  end

  # ==========================================================================
  # HTTP Timeout Override
  # ==========================================================================

  if timeout = System.get_env("TINK_TIMEOUT") do
    config :tink, timeout: String.to_integer(timeout)
  end

  # ==========================================================================
  # Production HTTP Pool
  # ==========================================================================
  # Set here (not prod.exs) for two reasons:
  #   1. count uses System.schedulers_online() which must reflect the actual
  #      production host, not the build machine.
  #   2. transport_opts calls :public_key.pkix_verify_hostname_match_fun/1
  #      which returns a closure — closures cannot be stored in compile-time config.

  pool_size =
    case System.get_env("TINK_POOL_SIZE") do
      nil -> 100
      value -> String.to_integer(value)
    end

  config :tink, Tink.Finch,
    pools: %{
      default: [
        size: pool_size,
        count: System.schedulers_online(),
        max_idle_time: :timer.minutes(5),
        protocol: :http2,
        conn_opts: [
          timeout: 30_000,
          transport_opts: [
            verify: :verify_peer,
            depth: 3,
            cacerts: :public_key.cacerts_get(),
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ],
            versions: [:"tlsv1.2", :"tlsv1.3"]
          ]
        ]
      ]
    }

  # ==========================================================================
  # Cache Configuration
  # ==========================================================================

  cache_enabled =
    case System.get_env("TINK_CACHE_ENABLED", "true") do
      "true" -> true
      "false" -> false
      _ -> true
    end

  cache_ttl =
    case System.get_env("TINK_CACHE_TTL") do
      nil -> :timer.minutes(5)
      value -> String.to_integer(value) * 1_000
    end

  cache_size =
    case System.get_env("TINK_CACHE_SIZE") do
      nil -> 5000
      value -> String.to_integer(value)
    end

  # 3-arg config form deep-merges keyword lists, preserving the per-resource
  # ttls map set in prod.exs.
  config :tink, :cache,
    enabled: cache_enabled,
    default_ttl: cache_ttl,
    max_size: cache_size

  # ==========================================================================
  # Rate Limiting
  # ==========================================================================

  rate_limit_enabled =
    case System.get_env("TINK_RATE_LIMIT_ENABLED", "true") do
      "true" -> true
      "false" -> false
      _ -> true
    end

  config :tink, enable_rate_limiting: rate_limit_enabled

  # ==========================================================================
  # JWT/Joken
  # ==========================================================================

  if jwt_secret = System.get_env("JWT_SECRET") do
    config :joken,
      default_signer: [
        signer_alg: System.get_env("JWT_ALGORITHM", "HS256"),
        key_pem: jwt_secret
      ]
  end

  # ==========================================================================
  # Error Tracking
  # ==========================================================================

  if sentry_dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: config_env(),
      enable_source_code_context: true,
      root_source_code_path: File.cwd!()
  end

  if appsignal_key = System.get_env("APPSIGNAL_PUSH_API_KEY") do
    config :appsignal, :config,
      active: true,
      name: "Tink",
      push_api_key: appsignal_key,
      env: config_env()
  end

  # ==========================================================================
  # Log Level
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
  # Debug Mode
  # ==========================================================================

  debug_mode =
    case System.get_env("TINK_DEBUG", "false") do
      "true" -> true
      "1" -> true
      _ -> false
    end

  config :tink, debug_mode: debug_mode
end

# =============================================================================
# Development Runtime Configuration
# =============================================================================

if config_env() == :dev do
  # Load credentials from env at runtime (avoids needing a recompile when
  # the env var changes — dev.exs reads these at compile time as a fallback).
  if client_id = System.get_env("TINK_CLIENT_ID") do
    config :tink, client_id: client_id
  end

  if client_secret = System.get_env("TINK_CLIENT_SECRET") do
    config :tink, client_secret: client_secret
  end

  if jwt_secret = System.get_env("JWT_SECRET") do
    config :joken,
      default_signer: [
        signer_alg: System.get_env("JWT_ALGORITHM", "HS256"),
        key_pem: jwt_secret
      ]
  end
end
