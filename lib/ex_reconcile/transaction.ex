defmodule ExReconcile.Transaction do
  @moduledoc """
  Represents a single financial transaction.

  ## Fields

  - `:id` - optional reference/correlation identifier (e.g. check number, payment reference).
    Used as the primary key when `match_on: [:id]` is set.
  - `:date` - optional `Date.t()` of the transaction.
  - `:amount` - required numeric amount. Use integers (e.g. cents) wherever possible to
    avoid floating-point precision issues during comparison.
  - `:description` - optional free-text narrative (payee name, memo, etc.).
  - `:meta` - arbitrary map for any extra fields you want to carry through (e.g. currency,
    account number, original CSV row). Not used in matching or diff output by default.

  ## Examples

      iex> ExReconcile.Transaction.new(amount: 1050, date: ~D[2024-03-01], description: "Coffee")
      %ExReconcile.Transaction{amount: 1050, date: ~D[2024-03-01], description: "Coffee"}

      iex> ExReconcile.Transaction.new(%{id: "TXN-42", amount: 5000})
      %ExReconcile.Transaction{id: "TXN-42", amount: 5000}
  """

  @enforce_keys [:amount]
  defstruct [:id, :date, :amount, :description, meta: %{}]

  @type t :: %__MODULE__{
          id: term() | nil,
          date: Date.t() | nil,
          amount: number(),
          description: String.t() | nil,
          meta: map()
        }

  @doc """
  Build a `Transaction` from a keyword list or map.

  Raises `KeyError` if `:amount` is missing.

  ## Examples

      iex> ExReconcile.Transaction.new(amount: 100)
      %ExReconcile.Transaction{amount: 100, meta: %{}}
  """
  @spec new(keyword() | map()) :: t()
  def new(fields) when is_list(fields), do: new(Map.new(fields))

  def new(%{} = fields) do
    fields = Map.new(fields, fn {k, v} -> {to_atom(k), v} end)
    struct!(__MODULE__, fields)
  end

  @doc """
  Returns a short human-readable label for display in diffs and reports.

  ## Examples

      iex> ExReconcile.Transaction.label(%ExReconcile.Transaction{amount: 1050, date: ~D[2024-01-15], description: "Coffee"})
      "[2024-01-15] Coffee 1050"
  """
  @spec label(t()) :: String.t()
  def label(%__MODULE__{} = txn) do
    prefix =
      [txn.date && "[#{txn.date}]", txn.description]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    if prefix == "", do: "#{txn.amount}", else: "#{prefix} #{txn.amount}"
  end

  defp to_atom(k) when is_atom(k), do: k
  defp to_atom(k) when is_binary(k), do: String.to_existing_atom(k)
end
