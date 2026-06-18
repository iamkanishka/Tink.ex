defmodule Tink.AuthToken do
  @moduledoc """
  Utilities for inspecting and managing `Tink.Client` access token state.

  Complements `Tink.Auth` by providing helpers to check expiry, extract
  scopes, and decide whether a token needs refreshing — without making
  any API calls.

  ## Example

      {:ok, client} = Tink.Auth.client_credentials(scope: "accounts:read transactions:read")

      Tink.AuthToken.expired?(client)
      # => false

      Tink.AuthToken.scopes(client)
      # => ["accounts:read", "transactions:read"]

      Tink.AuthToken.has_scope?(client, "transactions:read")
      # => true

      Tink.AuthToken.has_scope?(client, "payment:write")
      # => false

      Tink.AuthToken.seconds_until_expiry(client)
      # => 3542

      Tink.AuthToken.should_refresh?(client)
      # => false  (becomes true when < 5 min remain)

  """

  alias Tink.Client

  # Refresh when < 5 minutes remain
  @refresh_threshold_seconds 300

  # ── Expiry helpers ────────────────────────────────────────────────────────────

  @doc "Returns `true` if the token has expired."
  @spec expired?(Client.t()) :: boolean()
  defdelegate expired?(client), to: Client

  @doc """
  Returns the number of seconds until the token expires.
  Returns `nil` when no expiry is set (token lives forever).
  Returns `0` or a negative number when already expired.
  """
  @spec seconds_until_expiry(Client.t()) :: integer() | nil
  def seconds_until_expiry(%Client{expires_at: nil}), do: nil

  def seconds_until_expiry(%Client{expires_at: exp}) do
    DateTime.diff(exp, DateTime.utc_now(), :second)
  end

  @doc """
  Returns `true` when the token is within the refresh threshold (default 5 min)
  or has already expired.

  Use this to proactively refresh tokens before they expire mid-request:

      if Tink.AuthToken.should_refresh?(client) do
        {:ok, client} = Tink.Auth.client_credentials(scope: client.scope)
      end

  ## Options
  - `:threshold_seconds` — seconds before expiry to consider stale (default: 300)
  """
  @spec should_refresh?(Client.t(), keyword()) :: boolean()
  def should_refresh?(client, opts \\ []) do
    threshold = Keyword.get(opts, :threshold_seconds, @refresh_threshold_seconds)

    case seconds_until_expiry(client) do
      nil -> false
      seconds -> seconds <= threshold
    end
  end

  @doc """
  Returns a human-readable expiry string, e.g. `"expires in 59 min"`,
  `"expired 2 min ago"`, or `"no expiry"`.
  """
  @spec expiry_summary(Client.t()) :: String.t()
  def expiry_summary(%Client{expires_at: nil}), do: "no expiry"

  def expiry_summary(client) do
    case seconds_until_expiry(client) do
      s when s > 3600 -> "expires in #{div(s, 3600)}h #{div(rem(s, 3600), 60)}min"
      s when s > 60 -> "expires in #{div(s, 60)} min"
      s when s > 0 -> "expires in #{s}s"
      s when s == 0 -> "expiring now"
      s -> "expired #{abs(div(s, 60))} min ago"
    end
  end

  # ── Scope helpers ─────────────────────────────────────────────────────────────

  @doc """
  Returns the list of scopes granted to this token.
  Returns an empty list if no scope is set.
  """
  @spec scopes(Client.t()) :: [String.t()]
  def scopes(%Client{scope: nil}), do: []
  def scopes(%Client{scope: ""}), do: []

  def scopes(%Client{scope: scope}) when is_binary(scope) do
    scope
    |> String.split([" ", ","], trim: true)
    |> Enum.uniq()
  end

  @doc """
  Returns `true` if the token has the given scope.

  Handles both space-separated and comma-separated scope strings.

  ## Example

      Tink.AuthToken.has_scope?(client, "transactions:read")
      # => true

  """
  @spec has_scope?(Client.t(), String.t()) :: boolean()
  def has_scope?(%Client{} = client, scope) when is_binary(scope) do
    scope in scopes(client)
  end

  @doc """
  Returns `true` if the token has **all** of the given scopes.

  ## Example

      Tink.AuthToken.has_all_scopes?(client, ["accounts:read", "transactions:read"])
      # => true

  """
  @spec has_all_scopes?(Client.t(), [String.t()]) :: boolean()
  def has_all_scopes?(%Client{} = client, required_scopes) when is_list(required_scopes) do
    token_scopes = scopes(client)
    Enum.all?(required_scopes, &(&1 in token_scopes))
  end

  @doc """
  Returns the list of scopes from `required_scopes` that are missing from
  the token. Returns an empty list when all scopes are present.

  ## Example

      Tink.AuthToken.missing_scopes(client, ["accounts:read", "payment:write"])
      # => ["payment:write"]

  """
  @spec missing_scopes(Client.t(), [String.t()]) :: [String.t()]
  def missing_scopes(%Client{} = client, required_scopes) when is_list(required_scopes) do
    token_scopes = scopes(client)
    Enum.reject(required_scopes, &(&1 in token_scopes))
  end

  # ── Token metadata ────────────────────────────────────────────────────────────

  @doc """
  Returns a summary map for logging/debugging. Does NOT include the access token.

  ## Example

      Tink.AuthToken.summary(client)
      # => %{
      #   expired: false,
      #   expiry: "expires in 59 min",
      #   scope_count: 3,
      #   scopes: ["accounts:read", "transactions:read", "balances:read"],
      #   auto_refresh: false,
      #   cache: true
      # }

  """
  @spec summary(Client.t()) :: %{
          expired: boolean(),
          expiry: String.t(),
          scope_count: non_neg_integer(),
          scopes: [String.t()],
          auto_refresh: boolean(),
          cache: boolean()
        }
  def summary(%Client{} = client) do
    %{
      expired: expired?(client),
      expiry: expiry_summary(client),
      scope_count: length(scopes(client)),
      scopes: scopes(client),
      auto_refresh: client.auto_refresh,
      cache: client.cache
    }
  end
end
