defmodule ElibSQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :elibsql,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:db_connection, "~> 2.7.0"}
    ]
  end

  defp package do
    [
      maintainers: ["Michael Wang", "Kenneth Nguyen", "Christopher Nguyen"],
      description: "An Ecto adapter for libSQL",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/panda2k/elibsql"}
    ]
  end
end
