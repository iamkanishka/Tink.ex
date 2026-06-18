defmodule Tink.Application do
  @moduledoc false
  use Application

  alias Tink.{Config, RateLimiter}

  @impl true
  def start(_type, _args) do
    children =
      [
        {Finch, name: Tink.Finch, pools: finch_pools()},
        webhook_dispatcher_child()
      ]
      |> maybe_add_cache()
      |> maybe_add_rate_limiter()

    opts = [strategy: :one_for_one, name: Tink.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp finch_pools do
    %{
      "https://api.tink.com" => [size: 10, count: 1],
      "https://link.tink.com" => [size: 5, count: 1]
    }
  end

  # Only start Cachex if caching is enabled in config.
  #
  # NOTE: Cachex v4 removed the `:limit` start option and the `Cachex.Limit`
  # struct entirely (see Cachex's "Migrating to v4.x" guide). Cache size
  # limiting is now done via the `:hooks` option with a `Cachex.Limit.Scheduled`
  # (or `.Evented`) hook. We use `Cachex.Spec.hook/1` to build it.
  defp maybe_add_cache(children) do
    if Config.cache_enabled?() do
      import Cachex.Spec

      limit_hook =
        hook(
          module: Cachex.Limit.Scheduled,
          args: {
            Config.cache_max_size(),
            # options for Cachex.prune/3
            [],
            # options for Cachex.Limit.Scheduled (uses its default interval)
            []
          }
        )

      cache_child = {Cachex, name: :tink_cache, hooks: [limit_hook]}

      children ++ [cache_child]
    else
      children
    end
  end

  # Only start the Hammer ETS backend when rate limiting is enabled.
  #
  # IMPORTANT: starting this child is necessary but not sufficient. Hammer
  # also needs `config :hammer, backend: {Hammer.Backend.ETS, [...]}` set in
  # your application config so that `Hammer.check_rate/3` (called from
  # `Tink.RateLimiter`) knows which backend process to talk to. See
  # `config/config.exs` for the corresponding `:hammer` application config —
  # both must be kept in sync (in particular `expiry_ms`/`cleanup_interval_ms`
  # here should match the values configured for `:hammer`).
  defp maybe_add_rate_limiter(children) do
    if RateLimiter.enabled?() do
      hammer_child =
        {Hammer.Backend.ETS, [expiry_ms: :timer.hours(2), cleanup_interval_ms: :timer.minutes(10)]}

      children ++ [hammer_child]
    else
      children
    end
  end

  defp webhook_dispatcher_child do
    Tink.WebhookHandler.Dispatcher
  end
end
