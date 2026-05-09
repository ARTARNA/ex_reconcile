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

  # ---------------------------------------------------------------------------
  # Split matching (allow_splits: true)
  # ---------------------------------------------------------------------------

  describe "allow_splits: false (default)" do
    test "unmatched entries are NOT grouped into splits" do
      # One left of 300 vs three rights of 100 each — without splits they all stay unmatched
      left = [t(amount: 300, date: ~D[2024-01-01])]

      right = [
        t(amount: 100, date: ~D[2024-01-01]),
        t(amount: 100, date: ~D[2024-01-01]),
        t(amount: 100, date: ~D[2024-01-01])
      ]

      result = Matcher.run(left, right, cfg(match_on: [:amount]))
      assert result.splits == []
      assert length(result.unmatched_left) == 1
      assert length(result.unmatched_right) == 3
    end
  end

  describe "allow_splits: true — left-anchor splits (1 left : many rights)" do
    test "one left matches two rights that sum to its amount" do
      left = [t(amount: 300, date: ~D[2024-01-01])]
      right = [t(amount: 100, date: ~D[2024-01-02]), t(amount: 200, date: ~D[2024-01-03])]

      result = Matcher.run(left, right, cfg(match_on: [:amount], allow_splits: true))

      assert length(result.splits) == 1
      assert result.unmatched_left == []
      assert result.unmatched_right == []

      {anchor, parts} = hd(result.splits)
      assert anchor.amount == 300
      assert Enum.map(parts, & &1.amount) |> Enum.sort() == [100, 200]
    end

    test "one left matches three rights that sum to its amount" do
      left = [t(amount: 300)]
      right = [t(amount: 100), t(amount: 100), t(amount: 100)]

      result = Matcher.run(left, right, cfg(match_on: [:amount], allow_splits: true))

      assert length(result.splits) == 1
      {_anchor, parts} = hd(result.splits)
      assert length(parts) == 3
    end

    test "1:1 pairs are resolved first; remaining unmatched are split" do
      l1 = t(amount: 500, date: ~D[2024-01-01])
      l2 = t(amount: 300, date: ~D[2024-01-02])
      r1 = t(amount: 500, date: ~D[2024-01-01])
      r2 = t(amount: 100, date: ~D[2024-01-03])
      r3 = t(amount: 200, date: ~D[2024-01-04])

      result = Matcher.run([l1, l2], [r1, r2, r3], cfg(match_on: [:amount], allow_splits: true))

      assert length(result.matched) == 1
      assert length(result.splits) == 1
      assert result.unmatched_left == []
      assert result.unmatched_right == []
    end

    test "left-anchor split respects amount_tolerance" do
      # anchor = 300, parts = 99 + 200 = 299, delta = 1, tolerance = 2
      left = [t(amount: 300)]
      right = [t(amount: 99), t(amount: 200)]

      result =
        Matcher.run(left, right, cfg(match_on: [:amount], allow_splits: true, amount_tolerance: 2))

      assert length(result.splits) == 1
    end

    test "no split when sum falls outside amount_tolerance" do
      left = [t(amount: 300)]
      right = [t(amount: 90), t(amount: 200)]

      result =
        Matcher.run(left, right, cfg(match_on: [:amount], allow_splits: true, amount_tolerance: 2))

      assert result.splits == []
      assert length(result.unmatched_left) == 1
      assert length(result.unmatched_right) == 2
    end
  end

  describe "allow_splits: true — right-anchor splits (many lefts : 1 right)" do
    test "two lefts summing to one right form a split" do
      left = [t(amount: 100), t(amount: 200)]
      right = [t(amount: 300)]

      result = Matcher.run(left, right, cfg(match_on: [:amount], allow_splits: true))

      assert length(result.splits) == 1
      assert result.unmatched_left == []
      assert result.unmatched_right == []

      {parts, anchor} = hd(result.splits)
      assert anchor.amount == 300
      assert Enum.map(parts, & &1.amount) |> Enum.sort() == [100, 200]
    end
  end

  describe "allow_splits: true — no double-use of transactions" do
    test "a transaction used in a 1:1 match is not reused in a split" do
      # l1 matches r1 exactly; l2 + r2 could superficially look like parts of l1 too
      l1 = t(id: "A", amount: 300)
      l2 = t(id: "B", amount: 150)
      r1 = t(id: "A", amount: 300)
      r2 = t(id: "C", amount: 150)

      result =
        Matcher.run([l1, l2], [r1, r2], cfg(match_on: [:id], allow_splits: true))

      assert length(result.matched) == 1
      # l2 and r2 each stay unmatched; they don't form a split (only 2 single txns left,
      # neither side has a 1-vs-2 group)
      assert length(result.unmatched_left) == 1
      assert length(result.unmatched_right) == 1
      assert result.splits == []
    end

    test "each transaction appears in at most one split group" do
      # Two left-anchor splits: l1=300 → {r1=100, r2=200}, l2=250 → {r3=100, r4=150}
      l1 = t(id: "l1", amount: 300)
      l2 = t(id: "l2", amount: 250)
      r1 = t(id: "r1", amount: 100)
      r2 = t(id: "r2", amount: 200)
      r3 = t(id: "r3", amount: 100)
      r4 = t(id: "r4", amount: 150)

      result =
        Matcher.run([l1, l2], [r1, r2, r3, r4], cfg(match_on: [:amount], allow_splits: true))

      assert length(result.splits) == 2
      assert result.unmatched_left == []
      assert result.unmatched_right == []

      # Collect all right-side IDs used across both splits — no ID should appear twice
      all_part_ids =
        Enum.flat_map(result.splits, fn {_anchor, parts} -> Enum.map(parts, & &1.id) end)

      assert length(all_part_ids) == length(Enum.uniq(all_part_ids))
      assert Enum.sort(all_part_ids) == ["r1", "r2", "r3", "r4"]
    end
  end
end
