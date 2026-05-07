defmodule ExReconcile.MatcherTest do
  use ExUnit.Case, async: true

  alias ExReconcile.{Config, Matcher, Transaction}

  defp t(fields), do: Transaction.new(fields)
  defp cfg(opts \\ []), do: Config.new(opts)

  # ---------------------------------------------------------------------------
  # Empty inputs
  # ---------------------------------------------------------------------------

  describe "empty inputs" do
    test "both empty returns all empty result" do
      result = Matcher.run([], [], cfg())
      assert result.matched == []
      assert result.discrepancies == []
      assert result.unmatched_left == []
      assert result.unmatched_right == []
    end

    test "empty left puts all right in unmatched" do
      right = [t(amount: 100, date: ~D[2024-01-01])]
      result = Matcher.run([], right, cfg())
      assert result.unmatched_right == right
      assert result.matched == []
    end

    test "empty right puts all left in unmatched" do
      left = [t(amount: 200, date: ~D[2024-01-05])]
      result = Matcher.run(left, [], cfg())
      assert result.unmatched_left == left
    end
  end

  # ---------------------------------------------------------------------------
  # Exact matching (amount + date, default config)
  # ---------------------------------------------------------------------------

  describe "exact matching by amount and date" do
    test "single perfect match" do
      l = t(amount: 500, date: ~D[2024-02-10])
      r = t(amount: 500, date: ~D[2024-02-10])
      result = Matcher.run([l], [r], cfg())
      assert length(result.matched) == 1
      assert result.unmatched_left == []
      assert result.unmatched_right == []
    end

    test "multiple transactions, all match" do
      pairs = [
        {t(amount: 100, date: ~D[2024-01-01]), t(amount: 100, date: ~D[2024-01-01])},
        {t(amount: 200, date: ~D[2024-01-02]), t(amount: 200, date: ~D[2024-01-02])},
        {t(amount: 300, date: ~D[2024-01-03]), t(amount: 300, date: ~D[2024-01-03])}
      ]

      left = Enum.map(pairs, &elem(&1, 0))
      right = Enum.map(pairs, &elem(&1, 1))
      result = Matcher.run(left, right, cfg())
      assert length(result.matched) == 3
      assert result.unmatched_left == []
      assert result.unmatched_right == []
    end

    test "different amounts leaves both sides unmatched" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 999, date: ~D[2024-01-01])
      result = Matcher.run([l], [r], cfg())
      assert result.unmatched_left == [l]
      assert result.unmatched_right == [r]
    end

    test "same amount but different dates leaves both unmatched" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 100, date: ~D[2024-03-15])
      result = Matcher.run([l], [r], cfg())
      assert result.unmatched_left == [l]
      assert result.unmatched_right == [r]
    end
  end

  # ---------------------------------------------------------------------------
  # ID-based matching
  # ---------------------------------------------------------------------------

  describe "match_on: [:id]" do
    test "matches by id when all fields agree" do
      l = t(id: "REF-001", amount: 500, date: ~D[2024-01-10])
      r = t(id: "REF-001", amount: 500, date: ~D[2024-01-10])
      result = Matcher.run([l], [r], cfg(match_on: [:id]))
      assert length(result.matched) == 1
    end

    test "pairs by id even when dates differ, reports date as discrepancy" do
      l = t(id: "REF-001", amount: 500, date: ~D[2024-01-10])
      r = t(id: "REF-001", amount: 500, date: ~D[2024-01-12])
      result = Matcher.run([l], [r], cfg(match_on: [:id]))
      assert result.unmatched_left == []
      assert result.unmatched_right == []
      assert length(result.discrepancies) == 1
      {_l, _r, diffs} = hd(result.discrepancies)
      assert hd(diffs).field == :date
    end

    test "no match when ids differ" do
      l = t(id: "REF-001", amount: 500)
      r = t(id: "REF-002", amount: 500)
      result = Matcher.run([l], [r], cfg(match_on: [:id]))
      assert result.unmatched_left == [l]
      assert result.unmatched_right == [r]
    end

    test "no match when one id is nil" do
      l = t(id: nil, amount: 500)
      r = t(id: "REF-001", amount: 500)
      result = Matcher.run([l], [r], cfg(match_on: [:id]))
      assert result.unmatched_left == [l]
      assert result.unmatched_right == [r]
    end
  end

  # ---------------------------------------------------------------------------
  # Tolerance: amount
  # ---------------------------------------------------------------------------

  describe "amount_tolerance" do
    test "delta equal to tolerance is a clean match" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 105, date: ~D[2024-01-01])
      result = Matcher.run([l], [r], cfg(amount_tolerance: 5))
      assert length(result.matched) == 1
      assert result.discrepancies == []
    end

    test "no match when delta exceeds tolerance" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 106, date: ~D[2024-01-01])
      result = Matcher.run([l], [r], cfg(amount_tolerance: 5))
      assert result.unmatched_left == [l]
    end

    test "within-tolerance match is classified as matched, not discrepancy" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 103, date: ~D[2024-01-01])
      result = Matcher.run([l], [r], cfg(amount_tolerance: 5))
      # 3 <= 5, within tolerance, clean matched
      assert length(result.matched) == 1
      assert result.discrepancies == []
    end
  end

  # ---------------------------------------------------------------------------
  # Tolerance: date
  # ---------------------------------------------------------------------------

  describe "date_tolerance" do
    test "date delta equal to tolerance is a clean match" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 100, date: ~D[2024-01-03])
      result = Matcher.run([l], [r], cfg(date_tolerance: 2))
      assert length(result.matched) == 1
      assert result.discrepancies == []
    end

    test "no match when date delta exceeds tolerance" do
      l = t(amount: 100, date: ~D[2024-01-01])
      r = t(amount: 100, date: ~D[2024-01-04])
      result = Matcher.run([l], [r], cfg(date_tolerance: 2))
      assert result.unmatched_left == [l]
    end
  end

  # ---------------------------------------------------------------------------
  # Discrepancy detection
  # ---------------------------------------------------------------------------

  describe "discrepancies" do
    test "amount discrepancy detected when matched by id" do
      l = t(id: "X", amount: 1000)
      r = t(id: "X", amount: 1100)
      result = Matcher.run([l], [r], cfg(match_on: [:id]))
      assert length(result.discrepancies) == 1
      {_, _, diffs} = hd(result.discrepancies)
      assert [%{field: :amount, delta: 100}] = diffs
    end

    test "date discrepancy detected when matched by amount" do
      l = t(amount: 500, date: ~D[2024-01-01])
      r = t(amount: 500, date: ~D[2024-01-05])
      result = Matcher.run([l], [r], cfg(match_on: [:amount], date_tolerance: 0))
      assert length(result.discrepancies) == 1
      {_, _, diffs} = hd(result.discrepancies)
      assert Enum.any?(diffs, &(&1.field == :date))
    end

    test "description discrepancy detected" do
      l = t(amount: 100, date: ~D[2024-01-01], description: "Coffee Shop")
      r = t(amount: 100, date: ~D[2024-01-01], description: "COFFESHOP LTD")
      result = Matcher.run([l], [r], cfg())
      assert length(result.discrepancies) == 1
      {_, _, diffs} = hd(result.discrepancies)
      assert Enum.any?(diffs, &(&1.field == :description))
    end

    test "no description discrepancy when description_match: :ignore" do
      l = t(amount: 100, date: ~D[2024-01-01], description: "Coffee")
      r = t(amount: 100, date: ~D[2024-01-01], description: "Totally Different")
      result = Matcher.run([l], [r], cfg(description_match: :ignore))
      assert length(result.matched) == 1
      assert result.discrepancies == []
    end

    test "description discrepancy uses case_insensitive comparison by default" do
      l = t(amount: 100, date: ~D[2024-01-01], description: "Coffee")
      r = t(amount: 100, date: ~D[2024-01-01], description: "Tea")
      result = Matcher.run([l], [r], cfg(description_match: :case_insensitive))
      assert length(result.discrepancies) == 1
    end

    test "description comparison is case-insensitive and trimmed" do
      l = t(amount: 100, date: ~D[2024-01-01], description: "  Coffee  ")
      r = t(amount: 100, date: ~D[2024-01-01], description: "COFFEE")
      result = Matcher.run([l], [r], cfg())
      assert length(result.matched) == 1
      assert result.discrepancies == []
    end

    test "multiple discrepancies in one pair" do
      l = t(id: "Z", amount: 200, date: ~D[2024-01-01], description: "Alpha")
      r = t(id: "Z", amount: 300, date: ~D[2024-02-01], description: "Beta")
      result = Matcher.run([l], [r], cfg(match_on: [:id]))
      {_, _, diffs} = hd(result.discrepancies)
      fields = Enum.map(diffs, & &1.field)
      assert :amount in fields
      assert :date in fields
      assert :description in fields
    end
  end

  # ---------------------------------------------------------------------------
  # Greedy tie-breaking
  # ---------------------------------------------------------------------------

  describe "greedy matching picks the closest candidate" do
    test "prefers exact amount over near amount when both candidates exist" do
      left = t(amount: 100, date: ~D[2024-01-01])

      right_exact = t(amount: 100, date: ~D[2024-01-01])
      right_near = t(amount: 103, date: ~D[2024-01-01])

      result = Matcher.run([left], [right_exact, right_near], cfg(amount_tolerance: 5))
      [{_l, matched_r}] = result.matched
      assert matched_r.amount == 100
    end

    test "two lefts compete for the closer right" do
      l1 = t(amount: 100, date: ~D[2024-01-01])
      l2 = t(amount: 102, date: ~D[2024-01-01])
      r  = t(amount: 101, date: ~D[2024-01-01])

      result = Matcher.run([l1, l2], [r], cfg(amount_tolerance: 5))
      # Only one of l1/l2 gets matched; the other is unmatched_left
      assert length(result.matched) + length(result.discrepancies) == 1
      assert length(result.unmatched_left) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Ordering preservation
  # ---------------------------------------------------------------------------

  test "unmatched_left preserves original order" do
    lefts = [t(amount: 1), t(amount: 2), t(amount: 3)]
    result = Matcher.run(lefts, [], cfg())
    assert Enum.map(result.unmatched_left, & &1.amount) == [1, 2, 3]
  end

  test "unmatched_right preserves original order" do
    rights = [t(amount: 10), t(amount: 20), t(amount: 30)]
    result = Matcher.run([], rights, cfg())
    assert Enum.map(result.unmatched_right, & &1.amount) == [10, 20, 30]
  end
end
