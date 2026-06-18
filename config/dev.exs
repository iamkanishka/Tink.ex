import Config

# Development overrides — set TINK_CLIENT_ID / TINK_CLIENT_SECRET in .env
# Do NOT commit real credentials.
config :tink,
  client_id: System.get_env("TINK_CLIENT_ID", "dev_client_id"),
  client_secret: System.get_env("TINK_CLIENT_SECRET", "dev_client_secret")
