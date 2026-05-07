# ExReconcile

[![Hex.pm](https://img.shields.io/hexpm/v/ex_reconcile.svg)](https://hex.pm/packages/ex_reconcile)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ex_reconcile)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Ledger reconciliation for Elixir.

Given two lists of transactions (e.g. a bank export and an accounting system export),
**ExReconcile** finds matching pairs, surfaces discrepancies, and identifies transactions
that appear on only one side. Returns structured Elixir data you can act on programmatically.

**No runtime dependencies.**

---

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_reconcile, "~> 0.1"}
  ]
end
```

## Quick start

```elixir
alias ExReconcile.Transaction

bank = [
  Transaction.new(id: "B1", amount: 1050, date: ~D[2024-03-01], description: "Coffee"),
  Transaction.new(id: "B2", amount: 5000, date: ~D[2024-03-02], description: "Salary"),
  Transaction.new(id: "B3", amount: 200,  date: ~D[2024-03-05], description: "Subscription"),
]

ledger = [
  Transaction.new(id: "B1", amount: 1050, date: ~D[2024-03-01], description: "Coffee"),
  Transaction.new(id: "B2", amount: 4999, date: ~D[2024-03-02], description: "Salary"),  # amount off
  Transaction.new(id: "L4", amount: 75,   date: ~D[2024-03-06], description: "Parking"),  # only in ledger
]

result = ExReconcile.reconcile(bank, ledger, match_on: [:id])

IO.puts ExReconcile.format(result)
```

Output:

```
== Reconciliation Report [NEEDS ATTENTION] ==

  Matched              1
  Discrepancies        1
  Unmatched (left)     1
  Unmatched (right)    1

== Discrepancies ==
  1.
    Left:  [2024-03-02] Salary 5000
    Right: [2024-03-02] Salary 4999
      amount: 5000 -> 4999 (-1)

== Unmatched (left) ==
  - [2024-03-05] Subscription 200

== Unmatched (right) ==
  - [2024-03-06] Parking 75
```

---

## Transactions

A `Transaction` is a plain struct with five fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `:amount` | `number` | **yes** | Numeric amount. Use integers (e.g. cents) to avoid float precision issues. |
| `:date` | `Date.t()` | no | Calendar date of the transaction. |
| `:id` | `term` | no | Reference/correlation ID (check number, payment ref, etc.). |
| `:description` | `String.t()` | no | Payee name, memo, narrative. |
| `:meta` | `map` | no | Any extra fields; not used in matching. |

```elixir
Transaction.new(amount: 2500, date: ~D[2024-01-20], description: "AWS")
Transaction.new(%{"id" => "INV-99", "amount" => 10_000})  # string keys OK
```

---

## Matching options

Pass options as the third argument to `ExReconcile.reconcile/3`:

```elixir
ExReconcile.reconcile(left, right,
  match_on:          [:amount, :date],   # default
  amount_tolerance:  0,                  # default: exact
  date_tolerance:    0,                  # default: exact (days)
  description_match: :case_insensitive   # default
)
```

### `match_on`

Controls which fields must agree for two transactions to be considered a candidate pair.

| Value | Behaviour |
|---|---|
| `:id` | Both transactions must carry the same non-nil `:id`. |
| `:amount` | `abs(left.amount - right.amount) <= amount_tolerance` |
| `:date` | `abs(Date.diff(left.date, right.date)) <= date_tolerance` |
| `:description` | Descriptions must be equal (after trim + downcase). |

Default: `[:amount, :date]`

### Tolerances

```elixir
# Allow ±5 cents on amount, ±2 days on date
ExReconcile.reconcile(bank, ledger,
  match_on: [:amount, :date],
  amount_tolerance: 5,
  date_tolerance:   2
)
```

### `description_match`

- `:case_insensitive` (default) - descriptions are trimmed and lowercased before
  comparison. `"Coffee Shop"` and `"COFFEE SHOP"` are treated as equal; `"Coffee"` and
  `"Cafe"` are a discrepancy.
- `:ignore` - descriptions are skipped entirely in both matching and discrepancy checks.

---

## Result structure

`reconcile/3` returns an `%ExReconcile.Result{}`:

```elixir
%ExReconcile.Result{
  matched:          [{left_txn, right_txn}, ...],
  discrepancies:    [{left_txn, right_txn, [field_diff]}, ...],
  unmatched_left:   [txn, ...],
  unmatched_right:  [txn, ...]
}
```

Each `field_diff` describes a single field that differs:

```elixir
%{field: :amount,      left: 5000, right: 4999, delta: -1}
%{field: :date,        left: ~D[2024-01-01], right: ~D[2024-01-03], delta: 2}
%{field: :description, left: "Coffee",       right: "COFFESHOP LTD"}
```

### Helpers

```elixir
ExReconcile.Result.clean?(result)    # true iff no discrepancies and no unmatched
ExReconcile.Result.summary(result)
# => %{matched: 1, discrepancies: 1, unmatched_left: 1, unmatched_right: 1,
#       total_left: 3, total_right: 3}
```

---

## Matching algorithm

Pairs are found using a **greedy bipartite matching** strategy:

1. Generate all candidate pairs `(left, right)` where every `match_on` field is within
   tolerance.
2. Sort candidates by total distance (sum of field deltas), tightest matches first.
3. Greedily consume the best unassigned pair, mark both sides used, repeat.
4. Classify each pair: if all standard fields are within tolerance it goes into `matched`,
   otherwise `discrepancies`.

The candidate-generation step is O(n x m). For typical financial exports this is fast:
a 5,000 x 5,000 run generates at most 25 million candidate checks, each of which is a
handful of arithmetic comparisons. On a modern machine that completes in well under a
second. If you are processing very large datasets (100k+ rows) and need sub-second
latency, pre-filter by date range or account before calling `reconcile/3`.

## Duplicate transactions

When two transactions on the same side share the same match key (e.g. two payments for
the same amount on the same date), the greedy algorithm handles them in insertion order:

- **Both sides have duplicates** - each left duplicate is paired with one right
  duplicate. Surplus transactions end up unmatched.
- **Only one side has duplicates** - the first duplicate is paired; the rest appear in
  `unmatched_left` or `unmatched_right`.

```elixir
# Two identical bank rows, one ledger row
bank   = [Transaction.new(amount: 100, date: ~D[2024-01-01]),
          Transaction.new(amount: 100, date: ~D[2024-01-01])]
ledger = [Transaction.new(amount: 100, date: ~D[2024-01-01])]

result = ExReconcile.reconcile(bank, ledger)
length(result.matched)         # => 1
length(result.unmatched_left)  # => 1  (the second bank entry has no pair)
```

If you need to detect *all* duplicates as anomalies before reconciling, deduplicate or
group your input lists first.

---

## Formatting

```elixir
ExReconcile.format(result)
ExReconcile.format(result, title: "Bank vs QuickBooks", show_matched: true)
```

The formatter is purely a convenience. For custom reporting, pattern-match on
`result.discrepancies`, `result.unmatched_left`, etc. directly.

---

## Running tests

```sh
mix deps.get
mix test
```

Optional extras:

```sh
mix credo             # style checks
mix dialyzer          # type analysis
mix coveralls.html    # coverage report
```

---

## Contributing

Pull requests welcome. Please add tests for any new behaviour and run `mix test` and
`mix credo` before submitting.

---

## License

MIT. See [LICENSE](LICENSE).
