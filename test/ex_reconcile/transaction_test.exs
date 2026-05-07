defmodule ExReconcile.TransactionTest do
  use ExUnit.Case, async: true

  alias ExReconcile.Transaction

  describe "new/1 with keyword list" do
    test "creates a transaction with required amount" do
      txn = Transaction.new(amount: 100)
      assert txn.amount == 100
      assert txn.meta == %{}
    end

    test "accepts all optional fields" do
      txn = Transaction.new(id: "T1", amount: 500, date: ~D[2024-06-01], description: "Rent", meta: %{bank: "HSBC"})
      assert txn.id == "T1"
      assert txn.date == ~D[2024-06-01]
      assert txn.description == "Rent"
      assert txn.meta == %{bank: "HSBC"}
    end

    test "raises when amount is missing" do
      assert_raise ArgumentError, fn ->
        Transaction.new(description: "No amount")
      end
    end
  end

  describe "new/1 with map" do
    test "accepts atom-keyed map" do
      txn = Transaction.new(%{amount: 200, description: "Transfer"})
      assert txn.amount == 200
    end

    test "accepts string-keyed map" do
      txn = Transaction.new(%{"amount" => 300, "id" => "ref-9"})
      assert txn.amount == 300
      assert txn.id == "ref-9"
    end
  end

  describe "label/1" do
    test "includes date, description, and amount when all present" do
      txn = Transaction.new(amount: 1050, date: ~D[2024-01-15], description: "Coffee")
      assert Transaction.label(txn) == "[2024-01-15] Coffee 1050"
    end

    test "omits nil date" do
      txn = Transaction.new(amount: 999, description: "Taxi")
      assert Transaction.label(txn) == "Taxi 999"
    end

    test "omits nil description" do
      txn = Transaction.new(amount: 500, date: ~D[2024-03-01])
      assert Transaction.label(txn) == "[2024-03-01] 500"
    end

    test "shows only amount when date and description are nil" do
      txn = Transaction.new(amount: 42)
      assert Transaction.label(txn) == "42"
    end
  end
end
