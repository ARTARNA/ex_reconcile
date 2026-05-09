defmodule ExReconcile.Result do
  @moduledoc """
  The structured output of `ExReconcile.reconcile/3`.

  ## Fields

  - `:matched` - list of `{left, right}` pairs that were successfully reconciled with no
    field differences outside configured tolerances.
  - `:discrepancies` - list of `{left, right, [field_diff]}` tuples where the pair was
    matched (same key) but one or more fields differ beyond tolerance. Each `field_diff` is
    a map describing the field and the delta; see `t:field_diff/0`.
  - `:splits` - list of `t:split_match/0` tuples representing many-to-one matches found
    when `allow_splits: true`. Either one left transaction matched against multiple right
    transactions (`{left, [right1, right2, ...]}`), or multiple left transactions matched
    against one right transaction (`{[left1, left2, ...], right}`).
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

  @typedoc """
  A many-to-one split match. Either a single left transaction whose amount equals the sum
  of multiple right transactions, or multiple left transactions that sum to a single right.
  """
  @type split_match ::
          {Transaction.t(), [Transaction.t()]}
          | {[Transaction.t()], Transaction.t()}

  @type t :: %__MODULE__{
          matched: [pair()],
          discrepancies: [discrepancy()],
          splits: [split_match()],
          unmatched_left: [Transaction.t()],
          unmatched_right: [Transaction.t()]
        }

  defstruct matched: [],
            discrepancies: [],
            splits: [],
            unmatched_left: [],
            unmatched_right: []

  @doc """
  Returns a summary map with counts for each category.

  The `splits` count is the number of split groups (not the total number of transactions
  involved). The `total_left` and `total_right` counts include all transactions covered
  by split groups.

  ## Examples

      iex> result = %ExReconcile.Result{matched: [{"a", "b"}], unmatched_left: ["c"]}
      iex> ExReconcile.Result.summary(result)
      %{matched: 1, discrepancies: 0, splits: 0, unmatched_left: 1, unmatched_right: 0, total_left: 2, total_right: 1}
  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = r) do
    {split_left, split_right} =
      Enum.reduce(r.splits, {0, 0}, fn
        {_anchor, parts}, {lc, rc} when is_list(parts) -> {lc + 1, rc + length(parts)}
        {parts, _anchor}, {lc, rc} when is_list(parts) -> {lc + length(parts), rc + 1}
      end)

    %{
      matched: length(r.matched),
      discrepancies: length(r.discrepancies),
      splits: length(r.splits),
      unmatched_left: length(r.unmatched_left),
      unmatched_right: length(r.unmatched_right),
      total_left:
        length(r.matched) + length(r.discrepancies) + length(r.unmatched_left) + split_left,
      total_right:
        length(r.matched) + length(r.discrepancies) + length(r.unmatched_right) + split_right
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
