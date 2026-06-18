defmodule Tink.Users do
  @moduledoc """
  User management. Most operations require an application-level client
  (client credentials token) rather than a user token.

  ## Scopes
  - `user:create` — create users
  - `user:read` — get/list user data
  - `user:write` — update user data
  - `user:delete` — delete users
  """

  alias Tink.{Client, Error, Utils}

  @doc """
  Create a new permanent Tink user. Requires `user:create` scope.

  ## Params map keys
  - `"externalUserId"` — your system's user ID (required)
  - `"market"` — ISO 3166-1 alpha-2 market code, e.g. `"GB"`
  - `"locale"` — BCP 47 locale, e.g. `"en_US"`
  """
  @spec create_user(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_user(%Client{} = client, %{} = params) do
    body =
      %{}
      |> Utils.put_if_present(
        "externalUserId",
        params[:external_user_id] || params["externalUserId"]
      )
      |> Utils.put_if_present("market", params[:market] || params["market"])
      |> Utils.put_if_present("locale", params[:locale] || params["locale"])

    Client.post(client, "/api/v1/user/create", body)
  end

  @doc "Get the current authenticated user. Requires `user:read` scope."
  @spec get_user(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_user(%Client{} = client), do: Client.get(client, "/api/v1/user")

  @doc "Get the user profile. Requires `user:read` scope."
  @spec get_profile(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_profile(%Client{} = client), do: Client.get(client, "/api/v1/user/profile")

  @doc "Update user properties. Requires `user:write` scope."
  @spec update_user(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update_user(%Client{} = client, %{} = params), do: Client.put(client, "/api/v1/user", params)

  @doc "Update user profile. Requires `user:write` scope."
  @spec update_profile(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update_profile(%Client{} = client, %{} = params),
    do: Client.put(client, "/api/v1/user/profile", params)

  @doc """
  Delete a permanent Tink user and all their data. Requires `user:delete` scope.

  Returns `:ok` on success.
  """
  @spec delete_user(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_user(%Client{} = client, user_id) when is_binary(user_id) do
    case Client.post(client, "/api/v1/user/delete", %{"userId" => user_id}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
