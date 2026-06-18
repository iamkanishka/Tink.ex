defmodule Tink.Credentials do
  @moduledoc """
  Bank credential (connection) lifecycle management.

  A credential represents a user's authenticated connection to a bank via Tink.
  Credentials are created during a Tink Link flow and must be refreshed as
  bank consent periods expire.

  ## Scopes
  - `credentials:read` — list, get, QR
  - `credentials:write` — create, delete
  - `credentials:refresh` — refresh, authenticate, supplemental info
  """

  alias Tink.{Client, Error}

  @doc "List all credentials for the authenticated user. Requires `credentials:read`."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/api/v1/credentials/list")

  @doc "Get a specific credential by ID. Requires `credentials:read`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, credential_id) when is_binary(credential_id) do
    Client.get(client, "/api/v1/credentials/#{credential_id}")
  end

  @doc """
  Get the QR code for a credential. Used for some bank authentication flows.
  Requires `credentials:read`.
  """
  @spec get_qr(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_qr(%Client{} = client, credential_id) when is_binary(credential_id) do
    Client.get(client, "/api/v1/credentials/#{credential_id}/qr")
  end

  @doc "Create a new credential (bank connection). Requires `credentials:write`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/api/v1/credentials", params)
  end

  @doc "Delete a credential. Requires `credentials:write`."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{} = client, credential_id) when is_binary(credential_id) do
    case Client.delete(client, "/api/v1/credentials/#{credential_id}") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Trigger a data refresh for a credential. Requires `credentials:refresh`."
  @spec refresh(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def refresh(%Client{} = client, credential_id) when is_binary(credential_id) do
    Client.post(client, "/api/v1/credentials/#{credential_id}/refresh", %{})
  end

  @doc "Trigger re-authentication for a credential. Requires `credentials:refresh`."
  @spec authenticate(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def authenticate(%Client{} = client, credential_id) when is_binary(credential_id) do
    Client.post(client, "/api/v1/credentials/#{credential_id}/authenticate", %{})
  end

  @doc """
  Submit supplemental information for a credential (MFA / BankID / challenge response).
  Requires `credentials:refresh`.

  ## Example

      Tink.Credentials.submit_supplemental_info(client, credential_id, [
        %{"name" => "otp", "value" => "123456"}
      ])

  """
  @spec submit_supplemental_info(Client.t(), String.t(), list(map())) ::
          {:ok, map()} | {:error, Error.t()}
  def submit_supplemental_info(%Client{} = client, credential_id, fields)
      when is_binary(credential_id) and is_list(fields) do
    Client.post(
      client,
      "/api/v1/credentials/#{credential_id}/supplemental-information",
      %{"information" => fields}
    )
  end
end
