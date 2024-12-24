defmodule Tink.MixProject do
  use Mix.Project

    @source_url "https://github.com/iamkanishka/Tink.ex"
  @version "0.1.0"

  def project do
    [
      app: :tink,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Elixir Wrapper for Tink APIs: Seamlessly integrate with Tink's open banking platform to access financial data, manage payments, and enable innovative financial solutions.",
      package: package()
    ]
  end

  defp package do
    [
      name: "tink",
      # License, e.g., MIT, Apache 2.0
      licenses: ["Apache-2.0"],
      links: %{
        GitHub: @source_url
      },
      maintainers: ["Kanishka Naik"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
