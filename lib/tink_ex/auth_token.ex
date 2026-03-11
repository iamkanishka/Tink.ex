defmodule TinkEx.AuthToken do
  @moduledoc """
  Token expiration and management utilities.

  Provides functions for:
  - Checking token expiration
  - Calculating time until expiration
  - Token caching

  ## Examples

      iex> expires_at = DateTime.add(DateTime.utc_now(), 3600)
      iex> TinkEx.AuthToken.expired?(expires_at)
      false

      iex> TinkEx.AuthToken.expires_soon?(expires_at)
      false

      iex> TinkEx.AuthToken.time_until_expiration(expires_at)
      {:ok, 3600}
  """

  @buffer_seconds 300  # Refresh 5 minutes before expiration

  @doc """
  Checks if a token has expired.

  Returns `true` if the token is expired or will expire within the buffer period.

  ## Examples

      iex> future = DateTime.add(DateTime.utc_now(), 3600)
      iex> TinkEx.AuthToken.expired?(future)
      false

      iex> past = DateTime.add(DateTime.utc_now(), -60)
      iex> TinkEx.AuthToken.expired?(past)
      true

      iex> TinkEx.AuthToken.expired?(nil)
      true
  """
  @spec expired?(DateTime.t() | nil) :: boolean()
  def expired?(nil), do: true

  def expired?(%DateTime{} = expires_at) do
    buffer_time = DateTime.add(DateTime.utc_now(), @buffer_seconds)
    DateTime.compare(expires_at, buffer_time) in [:lt, :eq]
  end

  @doc """
  Checks if a token will expire soon (within buffer period).

  ## Examples

      iex> soon = DateTime.add(DateTime.utc_now(), 200)
      iex> TinkEx.AuthToken.expires_soon?(soon)
      true

      iex> later = DateTime.add(DateTime.utc_now(), 3600)
      iex> TinkEx.AuthToken.expires_soon?(later)
      false
  """
  @spec expires_soon?(DateTime.t() | nil) :: boolean()
  def expires_soon?(nil), do: true

  def expires_soon?(%DateTime{} = expires_at) do
    buffer_time = DateTime.add(DateTime.utc_now(), @buffer_seconds)
    DateTime.compare(expires_at, buffer_time) in [:lt, :eq]
  end

  @doc """
  Returns the number of seconds until token expiration.

  ## Examples

      iex> future = DateTime.add(DateTime.utc_now(), 3600)
      iex> {:ok, seconds} = TinkEx.AuthToken.time_until_expiration(future)
      iex> seconds > 3500
      true

      iex> TinkEx.AuthToken.time_until_expiration(nil)
      {:error, :no_expiration}
  """
  @spec time_until_expiration(DateTime.t() | nil) :: {:ok, integer()} | {:error, atom()}
  def time_until_expiration(nil), do: {:error, :no_expiration}

  def time_until_expiration(%DateTime{} = expires_at) do
    seconds = DateTime.diff(expires_at, DateTime.utc_now())
    {:ok, max(0, seconds)}
  end

  @doc """
  Calculates expiration time from expires_in seconds.

  ## Examples

      iex> TinkEx.AuthToken.calculate_expiration(3600)
      %DateTime{...}  # ~1 hour from now
  """
  @spec calculate_expiration(integer()) :: DateTime.t()
  def calculate_expiration(expires_in) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), expires_in, :second)
  end

  @doc """
  Gets the buffer period in seconds.

  ## Examples

      iex> TinkEx.AuthToken.buffer_seconds()
      300
  """
  @spec buffer_seconds() :: integer()
  def buffer_seconds, do: @buffer_seconds

  @doc """
  Parses a token response and extracts expiration time.

  ## Examples

      iex> response = %{"expires_in" => 3600, "access_token" => "token"}
      iex> TinkEx.AuthToken.parse_expiration(response)
      %DateTime{...}
  """
  @spec parse_expiration(map()) :: DateTime.t() | nil
  def parse_expiration(%{"expires_in" => expires_in}) when is_integer(expires_in) do
    calculate_expiration(expires_in)
  end

  def parse_expiration(_), do: nil
end
