defmodule Tink.Telemetry do
  @moduledoc """
  Telemetry integration. Attach handlers to these events in your application:

      :telemetry.attach("tink-requests", [:tink, :request, :stop], &MyApp.handle_tink_event/4, nil)

  ## Events

  - `[:tink, :request, :start]` — measurements: `%{system_time: integer}`, metadata: `%{method, url}`
  - `[:tink, :request, :stop]` — measurements: `%{duration: integer}`, metadata: `%{method, url, status}`
  - `[:tink, :cache, :hit]` — metadata: `%{key}`
  - `[:tink, :cache, :miss]` — metadata: `%{key}`
  - `[:tink, :rate_limit, :check]` — metadata: `%{key, allowed}`
  """

  alias Tink.Error

  @type method :: :get | :post | :put | :patch | :delete
  @type request_result :: {:ok, map()} | {:error, Error.t()}

  @doc "Emit `[:tink, :request, :start]`."
  @spec request_start(method(), String.t()) :: :ok
  def request_start(method, url) do
    :telemetry.execute(
      [:tink, :request, :start],
      %{system_time: System.system_time()},
      %{method: method, url: url}
    )
  end

  @doc "Emit `[:tink, :request, :stop]` with duration and derived status."
  @spec request_stop(method(), String.t(), request_result(), integer()) :: :ok
  def request_stop(method, url, result, duration) do
    status =
      case result do
        {:ok, _} -> :ok
        {:error, %{status: s}} -> s
        {:error, _} -> :error
      end

    :telemetry.execute(
      [:tink, :request, :stop],
      %{duration: duration},
      %{method: method, url: url, status: status}
    )
  end

  @doc "Emit `[:tink, :cache, :hit]`."
  @spec cache_hit(String.t()) :: :ok
  def cache_hit(key) do
    :telemetry.execute([:tink, :cache, :hit], %{}, %{key: key})
  end

  @doc "Emit `[:tink, :cache, :miss]`."
  @spec cache_miss(String.t()) :: :ok
  def cache_miss(key) do
    :telemetry.execute([:tink, :cache, :miss], %{}, %{key: key})
  end

  @doc "Emit `[:tink, :rate_limit, :check]`."
  @spec rate_limit_check(String.t(), boolean()) :: :ok
  def rate_limit_check(key, allowed) do
    :telemetry.execute([:tink, :rate_limit, :check], %{}, %{key: key, allowed: allowed})
  end
end
