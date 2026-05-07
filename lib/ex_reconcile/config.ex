defmodule ExReconcile.Config do
  @moduledoc """
  Configuration struct controlling how `ExReconcile.reconcile/3` behaves.

  Build one via `new/1` (or pass keyword options directly to `ExReconcile.reconcile/3`).

  ## Options

  | Option | Type | Default | Description |
  |---|---|---|---|
  | `:match_on` | `[atom]` | `[:amount, :date]` | Fields used to find candidate pairs. |
  | `:amount_tolerance` | `number` | `0` | Maximum absolute difference in amount that still counts as a match. |
  | `:date_tolerance` | `non_neg_integer` | `0` | Maximum absolute difference in days for date matching. |
  | `:description_match` | `:case_insensitive \\| :ignore` | `:case_insensitive` | How descriptions are compared when checking for discrepancies or matching. |

  ## Valid `match_on` fields

  - `:id` - match when both transactions carry the same non-nil `:id`.
  - `:amount` - match when `abs(left.amount - right.amount) <= amount_tolerance`.
  - `:date` - match when `abs(Date.diff(left.date, right.date)) <= date_tolerance`.
  - `:description` - match when descriptions are equal after normalisation (trim + downcase).

  ## Examples

      iex> ExReconcile.Config.new(match_on: [:id], amount_tolerance: 0)
      %ExReconcile.Config{match_on: [:id], amount_tolerance: 0, date_tolerance: 0, description_match: :case_insensitive}

      iex> ExReconcile.Config.new(match_on: [:amount, :date], date_tolerance: 2)
      %ExReconcile.Config{match_on: [:amount, :date], date_tolerance: 2, amount_tolerance: 0, description_match: :case_insensitive}
  """

  @valid_match_fields [:id, :amount, :date, :description]
  @valid_description_match [:case_insensitive, :ignore]

  @enforce_keys []
  defstruct match_on: [:amount, :date],
            amount_tolerance: 0,
            date_tolerance: 0,
            description_match: :case_insensitive

  @type description_match :: :case_insensitive | :ignore

  @type t :: %__MODULE__{
          match_on: [atom()],
          amount_tolerance: number(),
          date_tolerance: non_neg_integer(),
          description_match: description_match()
        }

  @doc """
  Create a `Config` from options, validating all values.

  Raises `ArgumentError` on invalid input.
  """
  @spec new(keyword() | map()) :: t()
  def new(opts \\ [])
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{} = opts) do
    config = struct!(__MODULE__, opts)
    validate!(config)
  end

  @doc false
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    invalid_fields = config.match_on -- @valid_match_fields

    if invalid_fields != [] do
      raise ArgumentError,
            "Invalid :match_on fields: #{inspect(invalid_fields)}. " <>
              "Valid fields are: #{inspect(@valid_match_fields)}"
    end

    if config.match_on == [] do
      raise ArgumentError, ":match_on must contain at least one field"
    end

    if not is_number(config.amount_tolerance) or config.amount_tolerance < 0 do
      raise ArgumentError, ":amount_tolerance must be a non-negative number"
    end

    if not is_integer(config.date_tolerance) or config.date_tolerance < 0 do
      raise ArgumentError, ":date_tolerance must be a non-negative integer"
    end

    if config.description_match not in @valid_description_match do
      raise ArgumentError,
            ":description_match must be one of #{inspect(@valid_description_match)}, " <>
              "got: #{inspect(config.description_match)}"
    end

    config
  end
end
