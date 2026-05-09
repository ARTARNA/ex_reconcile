defmodule ExReconcile.Matcher do
  @moduledoc false

  # Internal matching engine. Not part of the public API.
  #
  # Algorithm overview:
  #   1. Generate all candidate pairs (left × right) where every match_on field is
  #      within tolerance.
  #   2. Sort candidates by distance (ascending) so the tightest matches are tried first.
  #   3. Greedy assignment: consume the best unassigned pair, mark both sides used, repeat.
  #   4. Classify each assigned pair as :matched or :discrepancy by comparing ALL standard
  #      fields against the configured tolerances.
  #   5. When allow_splits: true, attempt to resolve remaining unmatched entries by finding
  #      groups whose amounts sum to a single transaction on the other side (many-to-one).

  # Maximum number of parts in a single split group. Guards against pathological subset-sum
  # search depth on large unmatched sets.
  @max_split_parts 20

  alias ExReconcile.{Config, Result, Transaction}

  @doc false
  @spec run([Transaction.t()], [Transaction.t()], Config.t()) :: Result.t()
  def run(left, right, %Config{} = config) do
    {pairs, unmatched_left, unmatched_right} = assign_pairs(left, right, config)

    {matched, raw_discrepancies} =
      Enum.split_with(pairs, fn {l, r} -> discrepancies(l, r, config) == [] end)

    discrepancies =
      Enum.map(raw_discrepancies, fn {l, r} -> {l, r, discrepancies(l, r, config)} end)

    {splits, final_unmatched_left, final_unmatched_right} =
      if config.allow_splits do
        find_splits(unmatched_left, unmatched_right, config)
      else
        {[], unmatched_left, unmatched_right}
      end

    %Result{
      matched: matched,
      discrepancies: discrepancies,
      splits: splits,
      unmatched_left: final_unmatched_left,
      unmatched_right: final_unmatched_right
    }
  end

  # ---------------------------------------------------------------------------
  # Pair assignment
  # ---------------------------------------------------------------------------

  defp assign_pairs(left, right, config) do
    indexed_left = Enum.with_index(left)
    indexed_right = Enum.with_index(right)

    candidates =
      for {l, li} <- indexed_left,
          {r, ri} <- indexed_right,
          candidate?(l, r, config) do
        {distance(l, r, config), li, ri, l, r}
      end

    candidates = Enum.sort_by(candidates, fn {dist, _, _, _, _} -> dist end)

    {pairs, used_left, used_right} =
      Enum.reduce(
        candidates,
        {[], MapSet.new(), MapSet.new()},
        fn {_dist, li, ri, l, r}, {pairs, ul, ur} ->
          if MapSet.member?(ul, li) or MapSet.member?(ur, ri) do
            {pairs, ul, ur}
          else
            {[{l, r} | pairs], MapSet.put(ul, li), MapSet.put(ur, ri)}
          end
        end
      )

    unmatched_left =
      indexed_left
      |> Enum.reject(fn {_, li} -> MapSet.member?(used_left, li) end)
      |> Enum.map(fn {t, _} -> t end)

    unmatched_right =
      indexed_right
      |> Enum.reject(fn {_, ri} -> MapSet.member?(used_right, ri) end)
      |> Enum.map(fn {t, _} -> t end)

    {Enum.reverse(pairs), unmatched_left, unmatched_right}
  end

  # ---------------------------------------------------------------------------
  # Candidate check: does this pair satisfy all match_on constraints?
  # ---------------------------------------------------------------------------

  defp candidate?(left, right, %Config{match_on: match_on} = config) do
    Enum.all?(match_on, &field_matches?(&1, left, right, config))
  end

  defp field_matches?(:id, left, right, _config) do
    not is_nil(left.id) and not is_nil(right.id) and left.id == right.id
  end

  defp field_matches?(:amount, left, right, %Config{amount_tolerance: tol}) do
    abs(left.amount - right.amount) <= tol
  end

  defp field_matches?(:date, left, right, %Config{date_tolerance: tol}) do
    not is_nil(left.date) and not is_nil(right.date) and
      abs(Date.diff(left.date, right.date)) <= tol
  end

  defp field_matches?(:description, left, right, %Config{description_match: :case_insensitive}) do
    not is_nil(left.description) and not is_nil(right.description) and
      normalize(left.description) == normalize(right.description)
  end

  defp field_matches?(:description, _left, _right, %Config{description_match: :ignore}),
    do: true

  # ---------------------------------------------------------------------------
  # Distance: lower = better match (used for greedy tie-breaking)
  # ---------------------------------------------------------------------------

  defp distance(left, right, %Config{match_on: match_on} = config) do
    Enum.sum(Enum.map(match_on, &field_distance(&1, left, right, config)))
  end

  defp field_distance(:id, _l, _r, _config), do: 0

  defp field_distance(:amount, left, right, _config),
    do: abs(left.amount - right.amount)

  defp field_distance(:date, left, right, _config)
       when not is_nil(left.date) and not is_nil(right.date),
       do: abs(Date.diff(left.date, right.date))

  defp field_distance(:date, _l, _r, _config), do: 0
  defp field_distance(:description, _l, _r, _config), do: 0

  # ---------------------------------------------------------------------------
  # Discrepancy detection: check ALL standard fields after pairing
  # ---------------------------------------------------------------------------

  defp discrepancies(left, right, %Config{} = config) do
    []
    |> check_amount(left, right, config)
    |> check_date(left, right, config)
    |> check_description(left, right, config)
  end

  defp check_amount(acc, left, right, %Config{amount_tolerance: tol}) do
    delta = right.amount - left.amount

    if abs(delta) > tol do
      [%{field: :amount, left: left.amount, right: right.amount, delta: delta} | acc]
    else
      acc
    end
  end

  defp check_date(acc, left, right, %Config{date_tolerance: tol}) do
    if not is_nil(left.date) and not is_nil(right.date) do
      delta = Date.diff(right.date, left.date)

      if abs(delta) > tol do
        [%{field: :date, left: left.date, right: right.date, delta: delta} | acc]
      else
        acc
      end
    else
      acc
    end
  end

  defp check_description(acc, _left, _right, %Config{description_match: :ignore}), do: acc

  defp check_description(acc, left, right, %Config{description_match: :case_insensitive}) do
    if not is_nil(left.description) and not is_nil(right.description) and
         normalize(left.description) != normalize(right.description) do
      [%{field: :description, left: left.description, right: right.description} | acc]
    else
      acc
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp normalize(str), do: str |> String.trim() |> String.downcase()

  # ---------------------------------------------------------------------------
  # Split matching: resolve remaining unmatched entries with many-to-one groups
  # ---------------------------------------------------------------------------

  # Two passes:
  #   1. Left-anchor: one unmatched left whose amount equals the sum of several rights.
  #   2. Right-anchor: one unmatched right whose amount equals the sum of several lefts.
  # Each transaction can only appear in one split group.
  defp find_splits(unmatched_left, unmatched_right, config) do
    {left_splits, rem_left, rem_right} =
      collect_splits(:left, unmatched_left, unmatched_right, config)

    {right_splits, final_left, final_right} =
      collect_splits(:right, rem_right, rem_left, config)

    {left_splits ++ right_splits, final_left, final_right}
  end

  # anchor_side :left  → anchors are left txns, parts are right txns
  # anchor_side :right → anchors are right txns (passed as first arg), parts are left txns
  defp collect_splits(anchor_side, anchors, parts, config) do
    indexed_anchors = Enum.with_index(anchors)
    indexed_parts = Enum.with_index(parts)

    {splits, used_anchor_idxs, used_part_idxs} =
      Enum.reduce(indexed_anchors, {[], MapSet.new(), MapSet.new()}, fn
        {anchor, ai}, {splits, used_a, used_p} ->
          available = Enum.reject(indexed_parts, fn {_, pi} -> MapSet.member?(used_p, pi) end)

          case find_sum_group(anchor.amount, available, config.amount_tolerance) do
            {:ok, group} ->
              part_idxs = MapSet.new(Enum.map(group, fn {_, pi} -> pi end))
              group_txns = Enum.map(group, fn {t, _} -> t end)
              split = build_split(anchor_side, anchor, group_txns)

              {[split | splits], MapSet.put(used_a, ai), MapSet.union(used_p, part_idxs)}

            :no_match ->
              {splits, used_a, used_p}
          end
      end)

    remaining_anchors =
      indexed_anchors
      |> Enum.reject(fn {_, i} -> MapSet.member?(used_anchor_idxs, i) end)
      |> Enum.map(&elem(&1, 0))

    remaining_parts =
      indexed_parts
      |> Enum.reject(fn {_, i} -> MapSet.member?(used_part_idxs, i) end)
      |> Enum.map(&elem(&1, 0))

    case anchor_side do
      :left -> {Enum.reverse(splits), remaining_anchors, remaining_parts}
      # For right-anchor pass the caller passed (right_anchors, left_parts), so we return
      # (splits, remaining_left_parts, remaining_right_anchors) to match the find_splits convention.
      :right -> {Enum.reverse(splits), remaining_parts, remaining_anchors}
    end
  end

  defp build_split(:left, anchor, group), do: {anchor, group}
  defp build_split(:right, anchor, group), do: {group, anchor}

  # Find a subset of indexed_txns of size >= 2 whose amounts sum within tolerance of target.
  # Returns {:ok, [indexed_txn]} or :no_match.
  # Uses backtracking with a depth cap to bound worst-case time on large unmatched sets.
  defp find_sum_group(target, indexed_txns, tolerance) do
    do_subset_sum(target, indexed_txns, tolerance, [], 0, 0)
  end

  defp do_subset_sum(target, [], tol, acc, sum, count) do
    if count >= 2 and abs(sum - target) <= tol,
      do: {:ok, Enum.reverse(acc)},
      else: :no_match
  end

  defp do_subset_sum(_target, _rest, _tol, _acc, _sum, count)
       when count >= @max_split_parts,
       do: :no_match

  defp do_subset_sum(target, [{txn, idx} | rest], tol, acc, sum, count) do
    case do_subset_sum(target, rest, tol, [{txn, idx} | acc], sum + txn.amount, count + 1) do
      {:ok, _} = found -> found
      :no_match -> do_subset_sum(target, rest, tol, acc, sum, count)
    end
  end
end
