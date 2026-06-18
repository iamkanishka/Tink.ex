defmodule Tink.Paginator do
  @moduledoc """
  Stream-based cursor pagination helpers.

  ## Usage

      # Lazy stream — fetches pages on demand
      Tink.Paginator.stream(fn page_token ->
        Tink.Transactions.list_transactions(client, page_token: page_token, page_size: 100)
      end, items_key: "transactions")
      |> Stream.filter(&(&1["type"] == "DEBIT"))
      |> Enum.take(500)

  """

  @type fetch_fn :: (String.t() | nil -> {:ok, map()} | {:error, any()})

  @spec stream(fetch_fn(), keyword()) :: Enumerable.t()
  def stream(fetch_fn, opts \\ []) do
    items_key = Keyword.get(opts, :items_key, "items")
    token_key = Keyword.get(opts, :token_key, "nextPageToken")

    Stream.resource(
      fn -> nil end,
      fn
        :done ->
          {:halt, :done}

        token ->
          fetch_page(fetch_fn, token, items_key, token_key)
      end,
      fn _ -> :ok end
    )
  end

  defp fetch_page(fetch_fn, token, items_key, token_key) do
    case fetch_fn.(token) do
      {:ok, page} ->
        items = Map.get(page, items_key, [])
        next_acc = next_token_or_done(Map.get(page, token_key))
        {items, next_acc}

      {:error, _} ->
        {:halt, :done}
    end
  end

  defp next_token_or_done(next) when next in [nil, ""], do: :done
  defp next_token_or_done(next), do: next

  @doc """
  Collect all pages eagerly and return `{:ok, all_items}`.
  Use `stream/2` for large datasets.
  """
  @spec collect_all(fetch_fn(), keyword()) :: {:ok, list()} | {:error, any()}
  def collect_all(fetch_fn, opts \\ []) do
    items_key = Keyword.get(opts, :items_key, "items")
    token_key = Keyword.get(opts, :token_key, "nextPageToken")
    do_collect(fetch_fn, nil, [], items_key, token_key)
  end

  defp do_collect(fetch_fn, token, acc, items_key, token_key) do
    case fetch_fn.(token) do
      {:ok, page} ->
        items = Map.get(page, items_key, [])
        next = Map.get(page, token_key)
        all = acc ++ items

        if next && next != "" do
          do_collect(fetch_fn, next, all, items_key, token_key)
        else
          {:ok, all}
        end

      {:error, _} = err ->
        err
    end
  end
end
