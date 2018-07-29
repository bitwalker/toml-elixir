defmodule Toml.MixProject do
  use Mix.Project

  def project do
    [
      app: :toml,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      description: "An implementation of TOML for Elixir projects",
      package: package(),
      deps: deps(),
      aliases: aliases(Mix.env),
      elixirc_paths: elixirc_paths(Mix.env),
      escript: escript(Mix.env)
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
    [{:jason, "~> 1.0", only: [:test]}]
  end

  defp package do
    [files: ["lib", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Paul Schoenfelder"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/bitwalker/toml-elixir"}]
  end
  
  defp escript(:test) do
    [
      main_module: Toml.CLI,
      name: :toml,
      path: Path.join([__DIR__, "bin", "toml"])
    ]
  end
  defp escript(_), do: nil
  
  defp aliases(_env) do
    [
      "test-all": ["test", "toml.tests"],
      clean: ["clean", &clean/1]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp clean(_args) do
    toml = Path.join([__DIR__, "bin", "toml"])
    if File.exists?(toml) do
      _ = File.rm(toml)
    end
  end
end
