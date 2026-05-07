defmodule ExReconcile.DiffTest do
  use ExUnit.Case, async: true

  alias ExReconcile.{Diff, Result, Transaction}

  defp t(fields), do: Transaction.new(fields)

  describe "format/2" do
    test "empty result shows CLEAN status" do
      output = Diff.format(%Result{})
      assert output =~ "CLEAN"
    end

    test "result with unmatched shows NEEDS ATTENTION" do
      result = %Result{unmatched_left: [t(amount: 100)]}
      output = Diff.format(result)
      assert output =~ "NEEDS ATTENTION"
    end

    test "summary counts appear in output" do
      result = %Result{
        matched: [{t(amount: 100), t(amount: 100)}],
        discrepancies: [],
        unmatched_left: [t(amount: 50)],
        unmatched_right: []
      }

      output = Diff.format(result)
      assert output =~ "Matched"
      assert output =~ "Unmatched (left)"
    end

    test "discrepancy section appears when discrepancies exist" do
      l = t(id: "A", amount: 100, date: ~D[2024-01-01])
      r = t(id: "A", amount: 200, date: ~D[2024-01-01])
      diffs = [%{field: :amount, left: 100, right: 200, delta: 100}]

      result = %Result{discrepancies: [{l, r, diffs}]}
      output = Diff.format(result)
      assert output =~ "Discrepancies"
      assert output =~ "amount"
      assert output =~ "+100"
    end

    test "unmatched_left section lists transactions" do
      txn = t(amount: 999, date: ~D[2024-06-15], description: "Rent")
      result = %Result{unmatched_left: [txn]}
      output = Diff.format(result)
      assert output =~ "Unmatched (left)"
      assert output =~ "999"
    end

    test "unmatched_right section lists transactions" do
      txn = t(amount: 42)
      result = %Result{unmatched_right: [txn]}
      output = Diff.format(result)
      assert output =~ "Unmatched (right)"
      assert output =~ "42"
    end

    test "matched section hidden by default" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 100, date: ~D[2024-01-01])
      result = %Result{matched: [{l, r}]}
      output = Diff.format(result)
      refute output =~ "== Matched =="
    end

    test "matched section shown when show_matched: true" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 100, date: ~D[2024-01-01])
      result = %Result{matched: [{l, r}]}
      output = Diff.format(result, show_matched: true)
      assert output =~ "== Matched =="
    end

    test "custom title appears in output" do
      output = Diff.format(%Result{}, title: "Bank vs Ledger")
      assert output =~ "Bank vs Ledger"
    end

    test "date discrepancy shows delta in days" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 100, date: ~D[2024-01-04])
      diffs = [%{field: :date, left: ~D[2024-01-01], right: ~D[2024-01-04], delta: 3}]
      result = %Result{discrepancies: [{l, r, diffs}]}
      output = Diff.format(result)
      assert output =~ "days"
    end

    test "description discrepancy shows both values" do
      l = t(amount: 100, date: ~D[2024-01-01], description: "Coffee")
      r = t(amount: 100, date: ~D[2024-01-01], description: "CAFE")
      diffs = [%{field: :description, left: "Coffee", right: "CAFE"}]
      result = %Result{discrepancies: [{l, r, diffs}]}
      output = Diff.format(result)
      assert output =~ "Coffee"
      assert output =~ "CAFE"
    end
  end
end
