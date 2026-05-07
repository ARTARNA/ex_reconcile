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

  alias ExReconcile.{Config, Result, Transaction}

  @doc false
  @spec run([Transaction.t()], [Transaction.t()], Config.t()) :: Result.t()
  def run(left, right, %Config{} = config) do
    {pairs, unmatched_left, unmatched_right} = assign_pairs(left, right, config)

    {matched, raw_discrepancies} =
      Enum.split_with(pairs, fn {l, r} -> discrepancies(l, r, config) == [] end)

    discrepancies =
      Enum.map(raw_discrepancies, fn {l, r} -> {l, r, discrepancies(l, r, config)} end)

    %Result{
      matched: matched,
      discrepancies: discrepancies,
      unmatched_left: unmatched_left,
      unmatched_right: unmatched_right
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
end
