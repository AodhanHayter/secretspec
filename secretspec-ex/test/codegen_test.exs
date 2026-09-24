defmodule SecretSpec.CodegenTest do
  # End-to-end typed-codegen pipeline:
  #
  #     secretspec schema -> quicktype -> AppSecrets.from_map(Resolved.fields(r))
  #
  # Proves the emitted schema drives quicktype to a typed struct whose decoder
  # consumes the runtime SDK's flat fields/1 map.
  use ExUnit.Case, async: true

  @moduletag :codegen
  @moduletag :tmp_dir

  @manifest """
  [project]
  name = "codegen-test"
  revision = "1.0"

  [profiles.default]
  DATABASE_URL = { description = "DB", required = true }
  DEV_SESSION_SECRET = { description = "Development-only session secret", required = false, default = "development-only-secret" }
  SENTRY_DSN = { description = "sentry", required = false }
  """

  test "quicktype types consume runtime fields", %{tmp_dir: dir} do
    manifest = Path.join(dir, "secretspec.toml")
    schema = Path.join(dir, "schema.json")
    generated = Path.join(dir, "app_secrets.ex")
    File.write!(manifest, @manifest)
    File.write!(Path.join(dir, ".env"), "DATABASE_URL=postgres://db\n")

    {_, 0} =
      System.cmd(System.fetch_env!("SECRETSPEC_BIN"), ["-f", manifest, "schema", "-o", schema])

    {_, 0} =
      System.cmd(
        "npx",
        ~w(--yes quicktype -s schema #{schema} --top-level AppSecrets --lang elixir -o #{generated}),
        stderr_to_stdout: true
      )

    [{app_secrets, _}] = Code.compile_file(generated)

    resolved =
      SecretSpec.builder()
      |> SecretSpec.with_path(manifest)
      |> SecretSpec.with_provider("dotenv://" <> Path.join(dir, ".env"))
      |> SecretSpec.with_reason("codegen test")
      |> SecretSpec.load!()

    typed = app_secrets.from_map(SecretSpec.Resolved.fields(resolved))
    assert typed.database_url == "postgres://db"
    assert typed.dev_session_secret == "development-only-secret"
    assert typed.sentry_dsn == nil
  end
end
