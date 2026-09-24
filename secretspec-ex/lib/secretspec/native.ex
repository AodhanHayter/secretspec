defmodule SecretSpec.Native do
  @moduledoc false
  # The Rustler NIF (native/secretspec_nif) that embeds the SecretSpec resolver.
  #
  # Released packages download a precompiled NIF for the host platform. Inside
  # this repository (dev/test) or with SECRETSPEC_BUILD=1 the NIF is compiled
  # from source instead, which needs a Rust toolchain.

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :secretspec,
    crate: "secretspec_nif",
    base_url: "https://github.com/cachix/secretspec/releases/download/v#{version}",
    version: version,
    force_build:
      Mix.env() in [:dev, :test] or System.get_env("SECRETSPEC_BUILD") in ["1", "true"],
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      x86_64-pc-windows-msvc
    ),
    mode: if(Mix.env() == :prod, do: :release, else: :debug)

  def resolve(_request_json), do: err()
  def call(_request_json), do: err()
  def abi_version, do: err()

  defp err, do: :erlang.nif_error(:nif_not_loaded)
end
