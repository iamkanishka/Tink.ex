import Config

# Runtime configuration — executed at startup in all environments.
# This is the correct place for secrets loaded from environment variables.

if config_env() == :prod do
  config :tink,
    client_id: System.fetch_env!("TINK_CLIENT_ID"),
    client_secret: System.fetch_env!("TINK_CLIENT_SECRET"),
    webhook_secret: System.get_env("TINK_WEBHOOK_SECRET")
end
