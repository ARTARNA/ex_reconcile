defmodule ExReconcile do
  @moduledoc """
  ExReconcile - ledger reconciliation for Elixir.

  Given two lists of `ExReconcile.Transaction` structs (e.g. a bank export and an
  accounting system export), `ExReconcile` finds matching pairs, surfaces discrepancies,
  and identifies transactions that appear in only one source.

  ## Quick start

      left = [
        ExReconcile.Transaction.new(id: "REF-1", amount: 1050, date: ~D[2024-01-15], description: "Coffee"),
        ExReconcile.Transaction.new(id: "REF-2", amount: 5000, date: ~D[2024-01-16], description: "Taxi")
      ]

      right = [
        ExReconcile.Transaction.new(id: "REF-1", amount: 1050, date: ~D[2024-01-15], description: "COFFEE SHOP"),
        ExReconcile.Transaction.new(id: "REF-3", amount: 200,  date: ~D[2024-01-17], description: "Unknown")
      ]

      result = ExReconcile.reconcile(left, right, match_on: [:id])
      # %ExReconcile.Result{
      #   matched:          [],
      #   discrepancies:    [{txn_ref1_left, txn_ref1_right, [%{field: :description, ...}]}],
      #   unmatched_left:   [txn_ref2],
      #   unmatched_right:  [txn_ref3]
      # }

      IO.puts ExReconcile.format(result)

  ## Matching strategies

  Control matching with the `:match_on` option and tolerance settings:

  ```elixir
  # Match on ID (exact), ignore description differences
  ExReconcile.reconcile(left, right,
    match_on: [:id],
    description_match: :ignore
  )

  # Match on amount + date, allow ±2 days and ±5 cents
  ExReconcile.reconcile(left, right,
    match_on: [:amount, :date],
    amount_tolerance: 5,
    date_tolerance: 2
  )
  ```

  See `ExReconcile.Config` for all available options.
  """

  alias ExReconcile.{Config, Diff, Matcher, Result}

  @doc """
  Reconcile two lists of transactions.

  Returns an `ExReconcile.Result` with four fields:

  - `:matched` - `[{left_txn, right_txn}]` perfectly reconciled pairs
  - `:discrepancies` - `[{left_txn, right_txn, [diff]}]` pairs that match by key but
    differ in one or more field values
  - `:unmatched_left` - transactions in `left` with no counterpart in `right`
  - `:unmatched_right` - transactions in `right` with no counterpart in `left`

  ## Options

  Accepts the same keyword options as `ExReconcile.Config.new/1`.

  | Option | Default |
  |---|---|
  | `:match_on` | `[:amount, :date]` |
  | `:amount_tolerance` | `0` |
  | `:date_tolerance` | `0` |
  | `:description_match` | `:case_insensitive` |

  ## Examples

      iex> alias ExReconcile.Transaction
      iex> left  = [Transaction.new(amount: 100, date: ~D[2024-01-01])]
      iex> right = [Transaction.new(amount: 100, date: ~D[2024-01-01])]
      iex> result = ExReconcile.reconcile(left, right)
      iex> length(result.matched)
      1
      iex> result.unmatched_left
      []

      iex> alias ExReconcile.Transaction
      iex> left  = [Transaction.new(id: "X1", amount: 100)]
      iex> right = [Transaction.new(id: "X1", amount: 105)]
      iex> result = ExReconcile.reconcile(left, right, match_on: [:id])
      iex> [{_l, _r, diffs}] = result.discrepancies
      iex> hd(diffs).field
      :amount
  """
  @spec reconcile([Transaction.t()], [Transaction.t()], keyword()) :: Result.t()
  def reconcile(left, right, opts \\ []) do
    config = Config.new(opts)
    Matcher.run(left, right, config)
  end

  @doc """
  Format a reconciliation result as a human-readable text report.

  ## Options

  - `:title` - report header. Defaults to `"Reconciliation Report"`.
  - `:show_matched` - include the full list of matched pairs. Defaults to `false`.

  ## Examples

      iex> result = ExReconcile.reconcile([], [])
      iex> ExReconcile.format(result) =~ "CLEAN"
      true
  """
  @spec format(Result.t(), keyword()) :: String.t()
  def format(%Result{} = result, opts \\ []) do
    Diff.format(result, opts)
  end
end
