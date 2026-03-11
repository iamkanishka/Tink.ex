defmodule TinkEx.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = build_children()

    opts = [strategy: :one_for_one, name: TinkEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp build_children do
    [
      # HTTP connection pool (Finch)
      {Finch, name: TinkEx.Finch, pools: finch_pools()},

      # Cache (if enabled)
      cache_child_spec()
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp finch_pools do
    # Get custom pool configuration or use defaults
    case Application.get_env(:tink_ex, TinkEx.Finch) do
      nil ->
        # Default pool configuration
        %{
          default: [
            size: pool_size(),
            count: pool_count(),
            conn_opts: [
              timeout: timeout(),
              transport_opts: transport_opts()
            ]
          ]
        }

      custom_pools ->
        custom_pools[:pools] || %{}
    end
  end

  defp pool_size do
    case Application.get_env(:tink_ex, :pool_size) do
      nil -> if Mix.env() == :test, do: 2, else: 32
      size -> size
    end
  end

  defp pool_count do
    case Mix.env() do
      :test -> 1
      :dev -> 1
      _ -> System.schedulers_online()
    end
  end

  defp timeout do
    Application.get_env(:tink_ex, :timeout, 30_000)
  end

  defp transport_opts do
    case Mix.env() do
      :prod ->
        # Production: Strict SSL/TLS
        [
          verify: :verify_peer,
          depth: 3,
          cacerts: :public_key.cacerts_get(),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ],
          versions: [:"tlsv1.2", :"tlsv1.3"]
        ]

      _ ->
        # Development/Test: Relaxed SSL
        [
          verify: :verify_peer,
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
    end
  end

  defp cache_child_spec do
    cache_config = Application.get_env(:tink_ex, :cache, [])
    enabled = Keyword.get(cache_config, :enabled, true)

    if enabled do
      max_size = Keyword.get(cache_config, :max_size, 1000)

      {Cachex, name: :tink_ex_cache, limit: max_size}
    else
      nil
    end
  end
end
