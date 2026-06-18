defmodule Tink.HTTP.MutualTLSTest do
  use ExUnit.Case, async: false

  alias Tink.HTTP.MutualTLS

  setup do
    original = Application.get_env(:tink, :mtls)
    on_exit(fn -> Application.put_env(:tink, :mtls, original || []) end)
    :ok
  end

  describe "finch_pools/0" do
    test "returns a pool config for api.tink.com" do
      Application.put_env(:tink, :mtls, [])
      pools = MutualTLS.finch_pools()
      assert Map.has_key?(pools, "https://api.tink.com")
    end

    test "includes TLS 1.3 and 1.2 in transport_opts versions" do
      Application.put_env(:tink, :mtls, [])
      pools = MutualTLS.finch_pools()
      transport_opts = pools["https://api.tink.com"][:transport_opts]
      versions = Keyword.get(transport_opts, :versions)
      assert :"tlsv1.3" in versions
      assert :"tlsv1.2" in versions
    end

    test "includes certfile/keyfile when configured via file paths" do
      Application.put_env(:tink, :mtls,
        cert_file: "/path/to/cert.pem",
        key_file: "/path/to/key.pem"
      )

      pools = MutualTLS.finch_pools()
      transport_opts = pools["https://api.tink.com"][:transport_opts]
      assert transport_opts[:certfile] == "/path/to/cert.pem"
      assert transport_opts[:keyfile] == "/path/to/key.pem"
    end

    test "works with no mtls config (defaults only)" do
      Application.put_env(:tink, :mtls, [])

      pools = MutualTLS.finch_pools()
      transport_opts = pools["https://api.tink.com"][:transport_opts]
      assert Keyword.has_key?(transport_opts, :versions)
      refute Keyword.has_key?(transport_opts, :cert)
      refute Keyword.has_key?(transport_opts, :certfile)
    end

    test "pool size and count are configured" do
      Application.put_env(:tink, :mtls, [])
      pools = MutualTLS.finch_pools()
      pool_cfg = pools["https://api.tink.com"]
      assert pool_cfg[:size] == 10
      assert pool_cfg[:count] == 1
    end
  end

  # Real ephemeral self-signed cert/key generated for tests only (not secrets).
  # Modern OpenSSL emits PKCS#8 ("PRIVATE KEY") by default, which decodes to
  # a `:PrivateKeyInfo` PEM entry — a good regression check that the key type
  # isn't hardcoded to `:RSAPrivateKey`.
  @test_cert """
  -----BEGIN CERTIFICATE-----
  MIIC/zCCAeegAwIBAgIUJBib/d+PELFiCOrv2JRTfYXQFAAwDQYJKoZIhvcNAQEL
  BQAwDzENMAsGA1UEAwwEdGVzdDAeFw0yNjA2MTcxMDA4NDVaFw0yNjA2MTgxMDA4
  NDVaMA8xDTALBgNVBAMMBHRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
  AoIBAQDTWLGaZ1p9vNqKbpUH8sE9xpodZkTWhfgnFSu0j2lN1cVSs8I0pQcupISo
  uwzY1kJ7uNUIyxD/v/W9e8fG1nUYvTUtE51494WZPGyfyJOcI9eJh4LMljlITpBf
  IG7bikaVSL3Ruec+iLC+1TfPxsDhYJOKOmNh5NgBwqDKjO3s4dLz5AjyttBpAb0J
  6TtxZF90/mUw/RwBlrCyMGkCgUlfJTNhfigaIYQhaJp0KI7X1cKyS/MUKijtFHz8
  1RqHu0+EFaQeh9XP9h7KvdMnEiIWNviB+6SVW2a4OKbNNI33CWpwIWxL6dA0emy8
  jE5CXZ41t6F6F7ePufu/Ty4a6PDBAgMBAAGjUzBRMB0GA1UdDgQWBBSYq3RPNjRF
  grApCiNRtf9RqdnVwTAfBgNVHSMEGDAWgBSYq3RPNjRFgrApCiNRtf9RqdnVwTAP
  BgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQB7WLIqKatgbRCdQl3T
  ugCz5pnrwiQL0bLpLPqqbk+JZ4xW9xA0pOH1hWkIPmnd7SSQui+qmsvE3RwVof2g
  AnSa58a9t/NONQM97WlR1m52T9FDCFEyBW9gAOnE0ptfd/5HK++IWz7eI649996L
  4B3J67aOqNE25y+0ySfPUvPtPfWVP/8CBB4e/gQ7Qfa4rlhWv/T4duu1d0UxwmnN
  CFQyYcjanx2sJpp9JJMtXUosrSKIorxAYAuPSTESQg0JNB+2O7Tfdj+0jCbrSbhI
  nqOuP/zj5/Arbh9LbnIcNCDKsS0ukP6PwjDn1KGu1up9CrbepbayU/69O3fEVaj/
  SDee
  -----END CERTIFICATE-----
  """

  @test_key """
  -----BEGIN PRIVATE KEY-----
  MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDTWLGaZ1p9vNqK
  bpUH8sE9xpodZkTWhfgnFSu0j2lN1cVSs8I0pQcupISouwzY1kJ7uNUIyxD/v/W9
  e8fG1nUYvTUtE51494WZPGyfyJOcI9eJh4LMljlITpBfIG7bikaVSL3Ruec+iLC+
  1TfPxsDhYJOKOmNh5NgBwqDKjO3s4dLz5AjyttBpAb0J6TtxZF90/mUw/RwBlrCy
  MGkCgUlfJTNhfigaIYQhaJp0KI7X1cKyS/MUKijtFHz81RqHu0+EFaQeh9XP9h7K
  vdMnEiIWNviB+6SVW2a4OKbNNI33CWpwIWxL6dA0emy8jE5CXZ41t6F6F7ePufu/
  Ty4a6PDBAgMBAAECggEALubwAyQMoPrYRQBlcm4dFGiOqxeXD0SL3aCFInzxEaTv
  NXtPDf/RqDg6eHeKUlS6TFqobFskWp1vG63sl+Pf+K2Er4w61i2YKHmQYaVRnMUX
  gB3imSR9cd59i57W+0GkiFysQ27OMsKC9ta6nBGvnFSiaXqrs33lsf5PUKQV6QuN
  Vsy21uvJquzLAzrsVpfuGYH53zdG5Z+/qu8Ce0dlO0b06To5tiZ/nOBW9AbQCgEz
  GmSecK2D+S0FYuNUs3wz4KfzECSi7l7vD1uPi7yckwwunJVhPuxBaBQ4Ey+aTEdx
  sBAYOwKY2TtWQs1Zfmc7Z9o2Xi3RaOEDX0wzy6CrQQKBgQDqXUgbrcVcRfYm5pM+
  //f6wpWC0z4DD59a/+SAz2awJIhC9scGWgzMiA0MuAkQ/TLlwCTJ3KriOlUG6LJd
  vHPRhTMpLcmG+6SCpPLPYgb0ida1LUMdeRcNQrViq0KW8ko4u3XKPowpvlbWnJAs
  TPK2gWls9VW+qZYvi3sX7zRXDwKBgQDm225YOVmlTb0weEh5vatlPB/iEEdMQYzJ
  QfM9WhOMgja0bUPk6XoAezlow8QsKuDfRsmBRe5v+tPDhysNgFmrHIdy6ZExfLMZ
  OHmku4kzd/HV56kTkS/I6FFqTb54o9YKtXvkUiyUOqRMpxpVAhP9r/twE3gxY2v1
  4MFx1/u7LwKBgQDmG96/5ndgKQUNnti2Q6bcXA9mWziI0t74/0UBQCIoEkaD0T8K
  uoHUlEST12J3ftNph6XXWUWjR/jSBsmShYUGFA1ughlb4lndOE17V1lS4r+gNieu
  mYULrRLhJRwFjzFW0KBPiege2Fb08tYP2SF6FkhIBf5BbMscNYwPrPqr+wKBgAdq
  OuQYi3mUwqPg6SsH3Y513OxM641WeagpNx/cWc5kjE9FRy3+Fc4YJyLnTtDAW9Kw
  Gl7NmTf9jXm1SLu5SKgHVY5qVCCLydDgkH+rCmAd1SWyuCqJukgwthS9BIYpdQGJ
  DL6rqQTl0Uso/t6GH5BBa8kQxwaHE/ukyXHXpx0/AoGBAIPtjxNlu1X6n0xAflAa
  UyS/XcmToLt8VvoT+kL8tUqd7E5daXjhzkUO+8Uv97fqMnq37uL6p2K8zd+g31Uu
  k4bYujLJ/LrfmN3F6Iy2znq/EzIYKZ3UmMzFg4Rz6sxi8/dVJyNuVE+65KIWBKQk
  rdJRhAJi1nPZRLcyzMDm2wTs
  -----END PRIVATE KEY-----
  """

  @test_ca """
  -----BEGIN CERTIFICATE-----
  MIIDBTCCAe2gAwIBAgIUSrkzX1eP2H6QlOTe5qoGa1Dqb/EwDQYJKoZIhvcNAQEL
  BQAwEjEQMA4GA1UEAwwHdGVzdC1jYTAeFw0yNjA2MTcxMDA4NDVaFw0yNjA2MTgx
  MDA4NDVaMBIxEDAOBgNVBAMMB3Rlc3QtY2EwggEiMA0GCSqGSIb3DQEBAQUAA4IB
  DwAwggEKAoIBAQC8IsmKkzd7fHQsCJGUJl+y5pamgc+ENb7j44DEuUNbCNTp3ZhF
  V9N8s+1j2wT4QYbT/kA7kVhC1HwKTObeV/Nn+z3UBNe6CskzotyxB89zd6yEpjfM
  IBitoPb8ozfua5neFNA2thmmAG5lEa3A+L++D4rASNcVoP7VpyKJWW2raQWTrs75
  TFrX03xapkLb1U7ds1D44ZNEZ+5Ki+gEJ7u7KZi4nFy5T/S8AaSbO/Uzk6FNBFvg
  wOtSq0iUe0v5VVHtnq1x/Q6OJUEn93yk+VWdxSJUBJFCQoyRYRLrt3gmDB+kI0QU
  VYUaBRdTaHplx/wKvNSWMBQJ1kF4s3cWGhhfAgMBAAGjUzBRMB0GA1UdDgQWBBSo
  VbdoKcwyDS6PSm+F5+B+54UV3jAfBgNVHSMEGDAWgBSoVbdoKcwyDS6PSm+F5+B+
  54UV3jAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQCKfPK00J0Q
  m2v0DBMnMPF49t5FSx00qJtWtx9edjeDXw7meZmc33QhCsAUi1OazVXI4C/vikZE
  a4OTOqMVsGy65pwtLl+M7FHvWbLVoTyi7PzEMuRZ4bxyLAtpQLGuHXlbsW6BdZcH
  We8Ao+GS9pXONMf0OSfR9S6DFvn2MIpXjqdMGQPZdsyh2L41ah/jb8tyxGgfw6/T
  p/0+qcgbDK8zUDKZdz18IYdaWPVv3eR4ysW1a6RG5Uq1JNiphJ3bDqZIj6LJGKrH
  p23B1XPoH7SDVADBMHKOkMK27ZLPTTrxF3ilOQxlLZW2jVjGIim8SehQRjxJsnB5
  uUG8YaWmDNH7
  -----END CERTIFICATE-----
  """

  describe "finch_pools/0 with cert_pem/key_pem (PEM string config)" do
    test "cert is the raw DER binary, not a decoded public_key record" do
      Application.put_env(:tink, :mtls, cert_pem: @test_cert, key_pem: @test_key)
      pools = MutualTLS.finch_pools()
      transport_opts = pools["https://api.tink.com"][:transport_opts]

      cert = transport_opts[:cert]
      assert is_binary(cert)

      # The DER binary must match what :public_key.pem_decode/1 extracts —
      # i.e. it must NOT have been passed through pem_entry_decode/1, which
      # would return a decoded #'Certificate'{} record tuple instead.
      [{:Certificate, expected_der, _}] = :public_key.pem_decode(@test_cert)
      assert cert == expected_der
    end

    test "key is {key_type, der} using the actual PEM entry type (PKCS#8 here)" do
      Application.put_env(:tink, :mtls, cert_pem: @test_cert, key_pem: @test_key)
      pools = MutualTLS.finch_pools()
      transport_opts = pools["https://api.tink.com"][:transport_opts]

      assert {key_type, key_der} = transport_opts[:key]
      assert is_binary(key_der)

      # OpenSSL's modern default key format is PKCS#8 ("PRIVATE KEY"), which
      # :public_key decodes as :PrivateKeyInfo — NOT :RSAPrivateKey. This
      # guards against hardcoding the key type.
      assert key_type == :PrivateKeyInfo
      [{:PrivateKeyInfo, expected_der, _}] = :public_key.pem_decode(@test_key)
      assert key_der == expected_der
    end

    test "cacerts is a list of raw DER binaries when ca_pem is configured" do
      Application.put_env(:tink, :mtls,
        cert_pem: @test_cert,
        key_pem: @test_key,
        ca_pem: @test_ca
      )

      pools = MutualTLS.finch_pools()
      transport_opts = pools["https://api.tink.com"][:transport_opts]

      assert [ca_der] = transport_opts[:cacerts]
      assert is_binary(ca_der)
      [{:Certificate, expected_der, _}] = :public_key.pem_decode(@test_ca)
      assert ca_der == expected_der
    end
  end

  describe "child_spec/0" do
    test "returns a Finch child spec tuple with mTLS pool name" do
      Application.put_env(:tink, :mtls, [])
      spec = MutualTLS.child_spec()
      assert {Finch, opts} = spec
      assert opts[:name] == Tink.Finch.MutualTLS
      assert Map.has_key?(opts[:pools], "https://api.tink.com")
    end
  end
end
