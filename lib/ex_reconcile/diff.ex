defmodule ExReconcile.Diff do
  @moduledoc """
  Formats a `ExReconcile.Result` as a human-readable text report.

  Use `ExReconcile.format/2` rather than calling this module directly.
  """

  alias ExReconcile.{Result, Transaction}

  @doc """
  Render a reconciliation result as a multi-line string.

  ## Options

  - `:title` - header title string. Defaults to `"Reconciliation Report"`.
  - `:show_matched` - whether to list every matched pair. Defaults to `false`.
  """
  @spec format(Result.t(), keyword()) :: String.t()
  def format(%Result{} = result, opts \\ []) do
    title = Keyword.get(opts, :title, "Reconciliation Report")
    show_matched = Keyword.get(opts, :show_matched, false)
    summary = Result.summary(result)

    sections = [
      render_header(title, summary),
      if(show_matched, do: render_matched(result.matched), else: nil),
      render_splits(result.splits),
      render_discrepancies(result.discrepancies),
      render_unmatched("Unmatched (left)", result.unmatched_left),
      render_unmatched("Unmatched (right)", result.unmatched_right)
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # ---------------------------------------------------------------------------
  # Sections
  # ---------------------------------------------------------------------------

  defp render_header(title, summary) do
    status =
      if summary.discrepancies == 0 and summary.unmatched_left == 0 and
           summary.unmatched_right == 0,
         do: "CLEAN",
         else: "NEEDS ATTENTION"

    """
    == #{title} [#{status}] ==

      Matched           #{pad(summary.matched)}
      Splits            #{pad(summary.splits)}
      Discrepancies     #{pad(summary.discrepancies)}
      Unmatched (left)  #{pad(summary.unmatched_left)}
      Unmatched (right) #{pad(summary.unmatched_right)}
    \
    """
  end

  defp render_matched([]), do: nil

  defp render_matched(pairs) do
    lines =
      Enum.map(pairs, fn {l, r} ->
        "  + #{Transaction.label(l)}  <->  #{Transaction.label(r)}"
      end)

    "\n== Matched ==\n" <> Enum.join(lines, "\n") <> "\n"
  end

  defp render_splits([]), do: nil

  defp render_splits(splits) do
    items =
      splits
      |> Enum.with_index(1)
      |> Enum.map(fn {split, idx} ->
        case split do
          {anchor, parts} when is_list(parts) ->
            part_lines = Enum.map(parts, fn p -> "      - #{Transaction.label(p)}" end)

            """
              #{idx}. [1:#{length(parts)}]
                Left:  #{Transaction.label(anchor)}
                Right:
            #{Enum.join(part_lines, "\n")}
            """

          {parts, anchor} when is_list(parts) ->
            part_lines = Enum.map(parts, fn p -> "      - #{Transaction.label(p)}" end)

            """
              #{idx}. [#{length(parts)}:1]
                Left:
            #{Enum.join(part_lines, "\n")}
                Right: #{Transaction.label(anchor)}
            """
        end
      end)

    "\n== Splits ==\n" <> Enum.join(items, "\n")
  end

  defp render_discrepancies([]), do: nil

  defp render_discrepancies(discrepancies) do
    items =
      discrepancies
      |> Enum.with_index(1)
      |> Enum.map(fn {{left, right, diffs}, idx} ->
        diff_lines = Enum.map(diffs, &render_field_diff/1)

        """
          #{idx}.
            Left:  #{Transaction.label(left)}
            Right: #{Transaction.label(right)}
        #{Enum.join(diff_lines, "\n")}
        """
      end)

    "\n== Discrepancies ==\n" <> Enum.join(items, "\n")
  end

  defp render_unmatched(_label, []), do: nil

  defp render_unmatched(label, txns) do
    lines = Enum.map(txns, fn t -> "  - #{Transaction.label(t)}" end)
    "\n== #{label} ==\n" <> Enum.join(lines, "\n") <> "\n"
  end

  defp render_field_diff(%{field: :amount, left: l, right: r, delta: d}) do
    sign = if d >= 0, do: "+", else: ""
    "      amount: #{l} -> #{r} (#{sign}#{d})"
  end

  defp render_field_diff(%{field: :date, left: l, right: r, delta: d}) do
    sign = if d >= 0, do: "+", else: ""
    "      date:   #{l} -> #{r} (#{sign}#{d} days)"
  end

  defp render_field_diff(%{field: :description, left: l, right: r}) do
    "      desc:   \"#{l}\" -> \"#{r}\""
  end

  defp pad(n), do: String.pad_leading("#{n}", 4)
end
