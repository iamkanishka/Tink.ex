defmodule Tink.HTTP.Behaviour do
  @moduledoc "Behaviour for HTTP adapters — swap Finch for test mocks."

  @type method :: :get | :post | :put | :patch | :delete
  @type headers :: [{String.t(), String.t()}]
  @type body :: String.t() | nil
  @type response ::
          {:ok, %{status: integer(), headers: headers(), body: String.t()}} | {:error, term()}

  @callback request(method(), String.t(), headers(), body(), keyword()) :: response()
end

defmodule Tink.HTTP.Finch do
  @moduledoc """
  Default Finch-backed HTTP adapter.

  Supports TLS 1.2+ (Tink will require TLS 1.3 after 31 December 2027).
  Configure via Tink.Config — the adapter is started in Tink.Application.
  """

  @behaviour Tink.HTTP.Behaviour

  alias Tink.Config

  @impl true
  def request(method, url, headers, body, opts) do
    timeout = Keyword.get(opts, :timeout, Config.timeout())
    finch_body = body || ""

    method
    |> Finch.build(url, headers, finch_body)
    |> Finch.request(Tink.Finch, receive_timeout: timeout)
    |> case do
      {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status: status, headers: resp_headers, body: resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule Tink.HTTP.MutualTLS do
  @moduledoc """
  Mutual TLS (mTLS) HTTP adapter for Tink.

  Tink accepts mTLS as an alternative to client_id/client_secret for OAuth
  client authentication (RFC 8705 interoperability requirement).

  ## Configuration

      # In config/runtime.exs:
      config :tink,
        http_adapter: Tink.HTTP.MutualTLS,
        mtls: [
          cert_pem:  System.get_env("TINK_CLIENT_CERT_PEM"),
          key_pem:   System.get_env("TINK_CLIENT_KEY_PEM"),
          ca_pem:    System.get_env("TINK_CA_PEM")   # optional; Tink uses DigiCert/Amazon CAs
        ]

  Or point to files:

      config :tink,
        http_adapter: Tink.HTTP.MutualTLS,
        mtls: [
          cert_file: "/path/to/client.crt",
          key_file:  "/path/to/client.key"
        ]

  ## CA Certificate notes (from Tink docs)

  Tink's API server certificate is issued by DigiCert. On 17 September 2026,
  DigiCert Global Root G2 (RSA SHA-256) will be replaced with Amazon Root CA 3
  (EC_prime256v1). Update your certificate trust store before that date.

  If using certificate pinning, ensure you trust:
  - DigiCert Global Root G2 (current)
  - Amazon Root CA 3 (from 17 Sep 2026)

  ## TLS version

  TLS 1.2 is currently required minimum. Tink will **stop accepting TLS 1.2**
  on **31 December 2027** — ensure your application supports TLS 1.3 before then.

  """

  @behaviour Tink.HTTP.Behaviour

  alias Tink.Config

  @impl true
  def request(method, url, headers, body, opts) do
    timeout = Keyword.get(opts, :timeout, Config.timeout())
    finch_body = body || ""
    finch_name = mtls_finch_name()

    method
    |> Finch.build(url, headers, finch_body)
    |> Finch.request(finch_name, receive_timeout: timeout)
    |> case do
      {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status: status, headers: resp_headers, body: resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Build the Finch mTLS pool configuration from app config."
  @spec finch_pools() :: %{String.t() => keyword()}
  def finch_pools do
    mtls_cfg = Application.get_env(:tink, :mtls, [])
    transport_opts = build_transport_opts(mtls_cfg)

    %{
      "https://api.tink.com" => [
        size: 10,
        count: 1,
        transport_opts: transport_opts
      ]
    }
  end

  @doc """
  Start a named Finch pool for mTLS. Call this in your Application supervisor.

  Returns a `{Finch, opts}` tuple suitable for a `Supervisor`/`Application`
  children list — NOT the formal `Supervisor.child_spec()` map shape (i.e.
  `%{id: ..., start: {mod, fun, args}, ...}`). `Finch` itself implements
  `child_spec/1` (via `use Supervisor`), so the children list entry
  `{Finch, opts}` is expanded into the real child spec by the supervisor at
  start time — this function just builds that entry, it doesn't build the
  expanded spec itself.
  """
  @spec child_spec() :: {module(), keyword()}
  def child_spec do
    {Finch, name: mtls_finch_name(), pools: finch_pools()}
  end

  defp mtls_finch_name, do: Tink.Finch.MutualTLS

  defp build_transport_opts(cfg) do
    opts = [versions: [:"tlsv1.3", :"tlsv1.2"]]

    opts =
      cond do
        cfg[:cert_pem] && cfg[:key_pem] ->
          # `:ssl`'s `:cert` option wants the raw DER-encoded binary (NOT a
          # decoded `public_key` record), and `:key` wants `{KeyType, der}`
          # where `KeyType` is whatever PEM entry type was actually present
          # (`'RSAPrivateKey'`, `'ECPrivateKey'`, or `'PrivateKeyInfo'` for
          # PKCS#8) — it must not be hardcoded to `:RSAPrivateKey`, since the
          # mTLS client key may be EC or PKCS#8-wrapped.
          {_cert_type, cert_der, _} = cfg[:cert_pem] |> :public_key.pem_decode() |> hd()

          {key_type, key_der, _} = cfg[:key_pem] |> :public_key.pem_decode() |> hd()

          Keyword.merge(opts, cert: cert_der, key: {key_type, key_der})

        cfg[:cert_file] && cfg[:key_file] ->
          Keyword.merge(opts, certfile: cfg[:cert_file], keyfile: cfg[:key_file])

        true ->
          opts
      end

    if cfg[:ca_pem] do
      # `:cacerts` expects a list of raw DER-encoded binaries, not decoded
      # `public_key` records.
      cacerts =
        cfg[:ca_pem]
        |> :public_key.pem_decode()
        |> Enum.map(fn {_type, der, _} -> der end)

      Keyword.put(opts, :cacerts, cacerts)
    else
      opts
    end
  end
end
