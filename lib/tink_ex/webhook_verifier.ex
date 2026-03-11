defmodule TinkEx.WebhookVerifier do
  @moduledoc """
  Webhook signature verification for Tink webhooks.

  Tink signs webhook payloads using HMAC-SHA256 to ensure authenticity.

  ## How It Works

  1. Tink generates a signature using your webhook secret
  2. Signature is sent in the `X-Tink-Signature` header
  3. You verify the signature matches the payload

  ## Security

  - Always verify signatures before processing webhooks
  - Use constant-time comparison to prevent timing attacks
  - Store webhook secret securely (environment variable)
  - Reject webhooks with invalid signatures

  ## Examples

      # Verify a webhook signature
      body = request_body
      signature = request_headers["x-tink-signature"]
      secret = System.get_env("TINK_WEBHOOK_SECRET")

      case TinkEx.WebhookVerifier.verify_signature(body, signature, secret) do
        :ok ->
          # Signature is valid, process webhook
          process_webhook(body)

        {:error, :invalid_signature} ->
          # Reject the webhook
          {:error, "Invalid signature"}
      end
  """

  require Logger

  @doc """
  Verifies a webhook signature.

  Uses constant-time comparison to prevent timing attacks.

  ## Parameters

    * `payload` - Raw webhook payload (string)
    * `signature` - Signature from `X-Tink-Signature` header
    * `secret` - Your webhook secret

  ## Returns

    * `:ok` - Signature is valid
    * `{:error, :invalid_signature}` - Signature is invalid
    * `{:error, :missing_signature}` - No signature provided

  ## Examples

      iex> payload = ~s({"type":"credentials.updated"})
      iex> secret = "webhook_secret_123"
      iex> signature = TinkEx.WebhookVerifier.generate_signature(payload, secret)
      iex> TinkEx.WebhookVerifier.verify_signature(payload, signature, secret)
      :ok

      iex> TinkEx.WebhookVerifier.verify_signature(payload, "invalid", secret)
      {:error, :invalid_signature}
  """
  @spec verify_signature(String.t(), String.t() | nil, String.t()) ::
          :ok | {:error, :invalid_signature | :missing_signature}
  def verify_signature(_payload, nil, _secret) do
    {:error, :missing_signature}
  end

  def verify_signature(_payload, "", _secret) do
    {:error, :missing_signature}
  end

  def verify_signature(payload, signature, secret)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) do
    expected_signature = generate_signature(payload, secret)

    if secure_compare(signature, expected_signature) do
      :ok
    else
      Logger.warning("[TinkEx.WebhookVerifier] Invalid webhook signature")
      {:error, :invalid_signature}
    end
  end

  @doc """
  Generates a signature for a payload.

  Useful for testing webhook handlers.

  ## Parameters

    * `payload` - Payload to sign (string)
    * `secret` - Webhook secret

  ## Returns

    Hexadecimal signature string

  ## Examples

      iex> payload = ~s({"type":"credentials.updated"})
      iex> secret = "webhook_secret_123"
      iex> TinkEx.WebhookVerifier.generate_signature(payload, secret)
      "a1b2c3d4e5f6..."
  """
  @spec generate_signature(String.t(), String.t()) :: String.t()
  def generate_signature(payload, secret) when is_binary(payload) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Validates webhook payload structure.

  Checks if the webhook has required fields.

  ## Parameters

    * `payload` - Parsed webhook payload (map)

  ## Returns

    * `:ok` - Payload is valid
    * `{:error, reason}` - Payload is invalid

  ## Examples

      iex> payload = %{"type" => "credentials.updated", "data" => %{}}
      iex> TinkEx.WebhookVerifier.validate_payload(payload)
      :ok

      iex> TinkEx.WebhookVerifier.validate_payload(%{})
      {:error, :missing_type}
  """
  @spec validate_payload(map()) :: :ok | {:error, atom()}
  def validate_payload(payload) when is_map(payload) do
    cond do
      not Map.has_key?(payload, "type") ->
        {:error, :missing_type}

      not Map.has_key?(payload, "data") ->
        {:error, :missing_data}

      true ->
        :ok
    end
  end

  def validate_payload(_), do: {:error, :invalid_payload}

  @doc """
  Checks if a webhook is a test webhook.

  Tink may send test webhooks to verify endpoint configuration.

  ## Examples

      iex> TinkEx.WebhookVerifier.test_webhook?(%{"type" => "test"})
      true

      iex> TinkEx.WebhookVerifier.test_webhook?(%{"type" => "credentials.updated"})
      false
  """
  @spec test_webhook?(map()) :: boolean()
  def test_webhook?(%{"type" => "test"}), do: true
  def test_webhook?(_), do: false

  # Private Functions

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(left, right) when is_binary(left) and is_binary(right) do
    if byte_size(left) == byte_size(right) do
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.reduce(0, fn {l, r}, acc -> acc ||| :crypto.exor(<<l>>, <<r>>) |> :binary.bin_to_list() |> hd() end)
      |> Kernel.==(0)
    else
      false
    end
  end
end
