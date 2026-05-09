# Changelog

All notable changes to ExReconcile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-05-09

### Added
- `allow_splits: true` option on `ExReconcile.reconcile/3` enables many-to-one matching
  after the standard 1:1 pass. A single transaction on one side can now be matched against
  a group of two or more transactions on the other side whose amounts sum to it (within
  `amount_tolerance`). Results are stored in `result.splits` as
  `ExReconcile.Result.split_match()` tuples and are excluded from `unmatched_left` /
  `unmatched_right`.
- `ExReconcile.Result.split_match/0` type — `{Transaction.t(), [Transaction.t()]}` for a
  left-anchor split and `{[Transaction.t()], Transaction.t()}` for a right-anchor split.
- `splits` field on `%ExReconcile.Result{}` (defaults to `[]`).
- `splits` key in `ExReconcile.Result.summary/1`; `total_left` and `total_right` counts
  now include transactions covered by split groups.
- `Splits` line in the `ExReconcile.format/2` text report header and a `== Splits ==`
  section listing each group with its `[1:N]` or `[N:1]` ratio.

## [0.1.0] - 2026-05-07

### Added
- `ExReconcile.Transaction` struct with `new/1` and `label/1` helpers.
- `ExReconcile.Config` with validation for `match_on`, `amount_tolerance`,
  `date_tolerance`, and `description_match` options.
- `ExReconcile.reconcile/3` - greedy bipartite matching engine with configurable
  field-level tolerances.
- `ExReconcile.Result` with `summary/1` and `clean?/1` helpers.
- `ExReconcile.format/2` - human-readable text diff report.
- Full ExUnit test suite.
