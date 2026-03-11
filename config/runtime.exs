import Config

# =============================================================================
# Runtime Configuration
# =============================================================================
# Executed at runtime (not compile time). Loaded AFTER prod.exs.
# All sensitive credentials and environment-specific overrides live here.

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
  # HTTP Pool Configuration
  # ==========================================================================

  # Set pool count at runtime so it reflects the actual host's scheduler count,
  # not the build machine's (System.schedulers_online() in prod.exs would
  # capture the build machine's value at compile time).
  pool_size = System.get_env("TINK_POOL_SIZE")

  config :tink, Tink.Finch,
    pools: %{
      default: [
        size: if(pool_size, do: String.to_integer(pool_size), else: 100),
        # Sized to match the VM's actual schedulers at runtime
        count: System.schedulers_online(),
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
        ],
        pool_opts: [
          max_idle_time: :timer.minutes(5),
          protocol: :http2
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

  # Uses the 3-arg config form which deep-merges keyword lists, preserving
  # the per-resource `ttls` map set in prod.exs.
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

  rate_limit_max =
    case System.get_env("TINK_RATE_LIMIT_MAX") do
      nil -> 100
      value -> String.to_integer(value)
    end

  # Uses the 3-arg form to deep-merge, preserving interval and strategy.
  config :tink, :rate_limit,
    enabled: rate_limit_enabled,
    max_requests: rate_limit_max

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
  # Debug Mode (for troubleshooting production issues)
  # ==========================================================================

  debug_mode =
    case System.get_env("TINK_DEBUG", "false") do
      "true" -> true
      "1" -> true
      _ -> false
    end

  config :tink, debug_mode: debug_mode

  # ==========================================================================
  # Staging-specific overrides
  # ==========================================================================

  if config_env() == :staging do
    # Staging logs at debug level for easier diagnostics
    config :logger, level: :debug

    # Use a smaller cache in staging to avoid stale data confusion
    config :tink, :cache,
      enabled: true,
      max_size: 1000
  end

  # ==========================================================================
  # Database (uncomment if using Ecto)
  # ==========================================================================

  # database_url =
  #   System.get_env("DATABASE_URL") ||
  #     raise """
  #     Environment variable DATABASE_URL is missing.
  #     For example: ecto://USER:PASS@HOST/DATABASE
  #     """
  #
  # maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []
  #
  # config :tink, Tink.Repo,
  #   url: database_url,
  #   pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  #   socket_options: maybe_ipv6
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
