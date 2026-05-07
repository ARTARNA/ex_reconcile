# Changelog

All notable changes to ExReconcile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
