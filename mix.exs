defmodule ExReconcile.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/ARTARNA/ex_reconcile"

  def project do
    [
      app: :ex_reconcile,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExReconcile",
      source_url: @source_url,
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Ledger reconciliation for Elixir: given two lists of transactions, find matches, detect discrepancies, and generate a structured diff."
  end

  defp package do
    [
      name: "ex_reconcile",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w[lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs]
    ]
  end

  defp docs do
    [
      main: "ExReconcile",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Data Structures": [ExReconcile.Transaction, ExReconcile.Result],
        Configuration: [ExReconcile.Config]
      ]
    ]
  end
end
