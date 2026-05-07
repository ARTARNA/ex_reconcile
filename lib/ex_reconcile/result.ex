defmodule ExReconcile.Result do
  @moduledoc """
  The structured output of `ExReconcile.reconcile/3`.

  ## Fields

  - `:matched` - list of `{left, right}` pairs that were successfully reconciled with no
    field differences outside configured tolerances.
  - `:discrepancies` - list of `{left, right, [field_diff]}` tuples where the pair was
    matched (same key) but one or more fields differ beyond tolerance. Each `field_diff` is
    a map describing the field and the delta; see `t:field_diff/0`.
  - `:unmatched_left` - transactions from the left list with no counterpart in the right.
  - `:unmatched_right` - transactions from the right list with no counterpart in the left.

  ## `field_diff` shape

  ```elixir
  # Amount discrepancy
  %{field: :amount, left: 1050, right: 1000, delta: -50}

  # Date discrepancy
  %{field: :date, left: ~D[2024-01-15], right: ~D[2024-01-16], delta: 1}

  # Description discrepancy
  %{field: :description, left: "Coffee Shop", right: "COFFESHOP LTD"}
  ```
  """

  alias ExReconcile.Transaction

  @type pair :: {Transaction.t(), Transaction.t()}

  @type field_diff ::
          %{field: :amount, left: number(), right: number(), delta: number()}
          | %{field: :date, left: Date.t(), right: Date.t(), delta: integer()}
          | %{field: :description, left: String.t(), right: String.t()}

  @type discrepancy :: {Transaction.t(), Transaction.t(), [field_diff()]}

  @type t :: %__MODULE__{
          matched: [pair()],
          discrepancies: [discrepancy()],
          unmatched_left: [Transaction.t()],
          unmatched_right: [Transaction.t()]
        }

  defstruct matched: [],
            discrepancies: [],
            unmatched_left: [],
            unmatched_right: []

  @doc """
  Returns a summary map with counts for each category.

  ## Examples

      iex> result = %ExReconcile.Result{matched: [{"a", "b"}], unmatched_left: ["c"]}
      iex> ExReconcile.Result.summary(result)
      %{matched: 1, discrepancies: 0, unmatched_left: 1, unmatched_right: 0, total_left: 2, total_right: 1}
  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = r) do
    %{
      matched: length(r.matched),
      discrepancies: length(r.discrepancies),
      unmatched_left: length(r.unmatched_left),
      unmatched_right: length(r.unmatched_right),
      total_left: length(r.matched) + length(r.discrepancies) + length(r.unmatched_left),
      total_right: length(r.matched) + length(r.discrepancies) + length(r.unmatched_right)
    }
  end

  @doc """
  Returns `true` when the reconciliation is clean: no discrepancies and no unmatched
  transactions on either side.

  ## Examples

      iex> ExReconcile.Result.clean?(%ExReconcile.Result{})
      true

      iex> ExReconcile.Result.clean?(%ExReconcile.Result{unmatched_left: [%ExReconcile.Transaction{amount: 1}]})
      false
  """
  @spec clean?(t()) :: boolean()
  def clean?(%__MODULE__{} = r) do
    r.discrepancies == [] and r.unmatched_left == [] and r.unmatched_right == []
  end
end
