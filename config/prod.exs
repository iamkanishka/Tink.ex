import Config

# Production — all secrets via runtime.exs / environment variables.
# Do not put secrets in this file.
config :tink,
  max_retries: 3,
  retry_delay: 500
