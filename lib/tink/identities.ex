defmodule Tink.Identities do
  @moduledoc """
  User identity data from the bank (verified name, address, date of birth).

  Requires `identity:read` (v1) or `identities:readonly` (v2) scope.
  Used for KYC, onboarding, and account verification flows.

  Identity data is bank-verified — it comes directly from the financial
  institution and reflects what they hold on file for the account holder.
  """

  alias Tink.{Client, Error}

  @doc """
  List identity records for the authenticated user (v1 API).
  Requires `identity:read` scope.
  """
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/api/v1/identities")

  @doc """
  List identity records for the authenticated user (v2 API).
  Requires `identities:readonly` scope.
  """
  @spec list_v2(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_v2(%Client{} = client), do: Client.get(client, "/data/v2/identities")
end
