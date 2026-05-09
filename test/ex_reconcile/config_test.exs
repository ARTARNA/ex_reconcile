defmodule ExReconcile.ConfigTest do
  use ExUnit.Case, async: true

  alias ExReconcile.Config

  describe "new/1" do
    test "returns defaults when called with no args" do
      config = Config.new()
      assert config.match_on == [:amount, :date]
      assert config.amount_tolerance == 0
      assert config.date_tolerance == 0
      assert config.description_match == :case_insensitive
      assert config.allow_splits == false
    end

    test "accepts valid match_on fields" do
      config = Config.new(match_on: [:id, :amount])
      assert config.match_on == [:id, :amount]
    end

    test "accepts amount_tolerance" do
      config = Config.new(amount_tolerance: 5)
      assert config.amount_tolerance == 5
    end

    test "accepts date_tolerance" do
      config = Config.new(date_tolerance: 3)
      assert config.date_tolerance == 3
    end

    test "accepts description_match :case_insensitive explicitly" do
      config = Config.new(description_match: :case_insensitive)
      assert config.description_match == :case_insensitive
    end

    test "accepts description_match :ignore" do
      config = Config.new(description_match: :ignore)
      assert config.description_match == :ignore
    end

    test "accepts allow_splits: true" do
      config = Config.new(allow_splits: true)
      assert config.allow_splits == true
    end

    test "accepts allow_splits: false explicitly" do
      config = Config.new(allow_splits: false)
      assert config.allow_splits == false
    end
  end

  describe "validate!" do
    test "raises on unknown match_on field" do
      assert_raise ArgumentError, ~r/Invalid :match_on fields/, fn ->
        Config.new(match_on: [:amount, :bogus_field])
      end
    end

    test "raises on empty match_on" do
      assert_raise ArgumentError, ~r/at least one field/, fn ->
        Config.new(match_on: [])
      end
    end

    test "raises on negative amount_tolerance" do
      assert_raise ArgumentError, ~r/amount_tolerance/, fn ->
        Config.new(amount_tolerance: -1)
      end
    end

    test "raises on non-integer date_tolerance" do
      assert_raise ArgumentError, ~r/date_tolerance/, fn ->
        Config.new(date_tolerance: 1.5)
      end
    end

    test "raises on invalid description_match value (e.g. old :exact atom)" do
      assert_raise ArgumentError, ~r/description_match/, fn ->
        Config.new(description_match: :exact)
      end
    end

    test "raises on other unknown description_match value" do
      assert_raise ArgumentError, ~r/description_match/, fn ->
        Config.new(description_match: :fuzzy)
      end
    end

    test "raises when allow_splits is not a boolean" do
      assert_raise ArgumentError, ~r/allow_splits/, fn ->
        Config.new(allow_splits: "yes")
      end
    end
  end
end
