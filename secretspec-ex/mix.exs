defmodule SecretSpec.MixProject do
  use Mix.Project

  @version "0.21.0"
  @source_url "https://github.com/cachix/secretspec"

  def project do
    [
      app: :secretspec,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Declarative secrets for Elixir, resolved by the SecretSpec Rust core",
      package: package(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:rustler_precompiled, "~> 0.9"},
      # Only needed to build the NIF from source (in this repository, or with
      # SECRETSPEC_BUILD=1); released packages download a precompiled NIF.
      {:rustler, "~> 0.38", optional: true, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      # The package lives in a subdirectory of the monorepo.
      source_url_pattern: "#{@source_url}/blob/v#{@version}/secretspec-ex/%{path}#L%{line}"
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url, "Docs" => "https://secretspec.dev/sdk/elixir/"},
      files: ~w(lib native/secretspec_nif/src native/secretspec_nif/Cargo.toml
                checksum-*.exs mix.exs README.md LICENSE)
    ]
  end
end
