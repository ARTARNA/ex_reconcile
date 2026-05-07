defmodule ExReconcileTest do
  use ExUnit.Case, async: true

  alias ExReconcile.Transaction

  defp t(fields), do: Transaction.new(fields)

  # ---------------------------------------------------------------------------
  # reconcile/2 - integration-level scenarios
  # ---------------------------------------------------------------------------

  describe "reconcile/2 - clean reconciliation" do
    test "identical single-item lists produce one matched pair and nothing else" do
      l = t(amount: 1000, date: ~D[2024-01-15])
      r = t(amount: 1000, date: ~D[2024-01-15])
      result = ExReconcile.reconcile([l], [r])
      assert length(result.matched) == 1
      assert result.discrepancies == []
      assert result.unmatched_left == []
      assert result.unmatched_right == []
    end

    test "result is clean?" do
      l = t(amount: 50, date: ~D[2024-04-01])
      r = t(amount: 50, date: ~D[2024-04-01])
      result = ExReconcile.reconcile([l], [r])
      assert ExReconcile.Result.clean?(result)
    end
  end

  describe "reconcile/2 - mixed result" do
    setup do
      bank = [
        t(id: "B1", amount: 1050, date: ~D[2024-03-01], description: "Coffee"),
        t(id: "B2", amount: 5000, date: ~D[2024-03-02], description: "Salary"),
        t(id: "B3", amount: 200,  date: ~D[2024-03-05], description: "Subscription")
      ]

      ledger = [
        t(id: "B1", amount: 1050, date: ~D[2024-03-01], description: "Coffee"),
        t(id: "B2", amount: 4999, date: ~D[2024-03-02], description: "Salary"),
        t(id: "L4", amount: 75,   date: ~D[2024-03-06], description: "Parking")
      ]

      %{bank: bank, ledger: ledger}
    end

    test "B1 matches cleanly", %{bank: bank, ledger: ledger} do
      result = ExReconcile.reconcile(bank, ledger, match_on: [:id])
      matched_ids = Enum.map(result.matched, fn {l, _r} -> l.id end)
      assert "B1" in matched_ids
    end

    test "B2 is a discrepancy (amount differs)", %{bank: bank, ledger: ledger} do
      result = ExReconcile.reconcile(bank, ledger, match_on: [:id])
      disc_ids = Enum.map(result.discrepancies, fn {l, _r, _d} -> l.id end)
      assert "B2" in disc_ids
    end

    test "B3 is unmatched in left (bank only)", %{bank: bank, ledger: ledger} do
      result = ExReconcile.reconcile(bank, ledger, match_on: [:id])
      unmatched_ids = Enum.map(result.unmatched_left, & &1.id)
      assert "B3" in unmatched_ids
    end

    test "L4 is unmatched in right (ledger only)", %{bank: bank, ledger: ledger} do
      result = ExReconcile.reconcile(bank, ledger, match_on: [:id])
      unmatched_ids = Enum.map(result.unmatched_right, & &1.id)
      assert "L4" in unmatched_ids
    end
  end

  describe "reconcile/3 - tolerance options" do
    test "within-amount-tolerance pair is a clean match" do
      left  = [t(amount: 100, date: ~D[2024-01-01])]
      right = [t(amount: 102, date: ~D[2024-01-01])]
      result = ExReconcile.reconcile(left, right, amount_tolerance: 5)
      assert length(result.matched) == 1
      assert result.discrepancies == []
    end

    test "outside-amount-tolerance pair is unmatched" do
      left  = [t(amount: 100, date: ~D[2024-01-01])]
      right = [t(amount: 110, date: ~D[2024-01-01])]
      result = ExReconcile.reconcile(left, right, amount_tolerance: 5)
      assert result.unmatched_left == left
    end

    test "within-date-tolerance pair is a clean match" do
      left  = [t(amount: 100, date: ~D[2024-01-01])]
      right = [t(amount: 100, date: ~D[2024-01-03])]
      result = ExReconcile.reconcile(left, right, date_tolerance: 3)
      assert length(result.matched) == 1
      assert result.discrepancies == []
    end
  end

  # ---------------------------------------------------------------------------
  # format/2 - smoke test from the top-level API
  # ---------------------------------------------------------------------------

  describe "format/2" do
    test "returns a non-empty string" do
      result = ExReconcile.reconcile([], [])
      output = ExReconcile.format(result)
      assert is_binary(output)
      assert String.length(output) > 0
    end

    test "CLEAN report for a perfect reconciliation" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 100, date: ~D[2024-01-01])
      result = ExReconcile.reconcile([l], [r])
      assert ExReconcile.format(result) =~ "CLEAN"
    end

    test "NEEDS ATTENTION when there are discrepancies" do
      l = t(id: "X", amount: 100)
      r = t(id: "X", amount: 200)
      result = ExReconcile.reconcile([l], [r], match_on: [:id])
      assert ExReconcile.format(result) =~ "NEEDS ATTENTION"
    end
  end

  # ---------------------------------------------------------------------------
  # Result.summary/1
  # ---------------------------------------------------------------------------

  describe "Result.summary/1" do
    test "totals are consistent" do
      bank = [
        t(amount: 100, date: ~D[2024-01-01]),
        t(amount: 200, date: ~D[2024-01-02]),
        t(amount: 300, date: ~D[2024-01-03])
      ]

      ledger = [
        t(amount: 100, date: ~D[2024-01-01]),
        t(amount: 999, date: ~D[2024-01-02])
      ]

      result = ExReconcile.reconcile(bank, ledger)
      summary = ExReconcile.Result.summary(result)

      assert summary.total_left == length(bank)
      assert summary.total_right == length(ledger)
      assert summary.matched + summary.discrepancies + summary.unmatched_left == length(bank)
    end
  end
end
