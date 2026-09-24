defmodule SecretSpecTest do
  use ExUnit.Case, async: false

  alias SecretSpec.{CallerContext, Error, MissingRequiredError, ResolvedSecret}

  @moduletag :tmp_dir

  @manifest """
  [project]
  name = "ex-test"
  revision = "1.0"

  [profiles.default]
  DATABASE_URL = { description = "DB", required = true }
  DEV_SESSION_SECRET = { description = "Development-only session secret", required = false, default = "development-only-secret" }
  SENTRY_DSN = { description = "sentry", required = false }

  [scopes.database]
  secrets = ["DATABASE_URL"]
  """

  defp project(dir, dotenv, manifest \\ @manifest) do
    File.write!(Path.join(dir, "secretspec.toml"), manifest)
    File.write!(Path.join(dir, ".env"), dotenv)

    SecretSpec.builder()
    |> SecretSpec.with_path(Path.join(dir, "secretspec.toml"))
    |> SecretSpec.with_provider("dotenv://" <> Path.join(dir, ".env"))
    |> SecretSpec.with_reason("ex test")
  end

  # The BEAM ignores SIGCHLD, which makes the kernel reap provider CLIs before
  # Rust can wait on them ("No child processes"). A fake `pass` exercises the
  # subprocess path that 1Password, LastPass, Bitwarden, etc. share.
  @tag :unix
  test "CLI-backed providers can run subprocesses", %{tmp_dir: dir} do
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)
    File.write!(Path.join(bin, "pass"), "#!/bin/sh\necho \"from-pass-$2\"\n")
    File.chmod!(Path.join(bin, "pass"), 0o755)
    project(dir, "")

    # System.put_env/2 does not reach the NIF's OS environment, so run the
    # check in a child VM whose PATH finds the fake CLI first.
    code = """
    b = SecretSpec.builder(path: #{inspect(Path.join(dir, "secretspec.toml"))}, provider: "pass://", scope: "database")

    1..8
    |> Task.async_stream(fn _ -> SecretSpec.load!(b).secrets["DATABASE_URL"].value end, max_concurrency: 4)
    |> Enum.each(fn {:ok, v} -> IO.puts(v) end)
    """

    ebins =
      Mix.Project.build_path()
      |> Path.join("lib/*/ebin")
      |> Path.wildcard()
      |> Enum.flat_map(&["-pa", &1])

    {out, status} =
      System.cmd(System.find_executable("elixir"), ebins ++ ["-e", code],
        env: [{"PATH", bin <> ":" <> System.get_env("PATH")}],
        stderr_to_stdout: true
      )

    assert {status, String.split(out, "\n", trim: true)} ==
             {0, List.duplicate("from-pass-secretspec/ex-test/default/DATABASE_URL", 8)}
  end

  test "abi_version is non-empty" do
    assert SecretSpec.abi_version() != ""
  end

  test "caller context is structured and separate from reason" do
    builder =
      SecretSpec.with_caller(SecretSpec.builder(), %CallerContext{
        name: "git",
        version: "2.51.0",
        operation: "credential_get",
        resource: "github.com"
      })

    assert builder.request == %{
             "caller" => %{
               name: "git",
               version: "2.51.0",
               operation: "credential_get",
               resource: "github.com"
             }
           }
  end

  test "load returns values and provenance", %{tmp_dir: dir} do
    {:ok, resolved} = dir |> project("DATABASE_URL=postgres://db\n") |> SecretSpec.load()

    assert resolved.profile == "default"
    db = resolved.secrets["DATABASE_URL"]
    assert ResolvedSecret.get(db) == "postgres://db"
    assert db.source == :provider
    assert db.source_provider

    session = resolved.secrets["DEV_SESSION_SECRET"]
    assert ResolvedSecret.get(session) == "development-only-secret"
    assert session.source == :default

    assert resolved.missing_optional == ["SENTRY_DSN"]
    refute Map.has_key?(resolved.secrets, "SENTRY_DSN")
  end

  test "inline spec resolves at its logical base_dir", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "inline.env"), "TOKEN=inline-elixir\n")

    spec = %{
      "project" => %{"name" => "elixir-inline"},
      "providers" => %{"env" => "dotenv://inline.env"},
      "profiles" => %{
        "default" => %{
          "secrets" => %{"TOKEN" => %{"description" => "token", "providers" => ["env"]}}
        }
      }
    }

    builder =
      SecretSpec.builder()
      |> SecretSpec.with_inline_spec(spec, dir)
      |> SecretSpec.with_reason("elixir inline test")

    resolved = SecretSpec.load!(builder)
    assert ResolvedSecret.get(resolved.secrets["TOKEN"]) == "inline-elixir"

    # Report mode travels inside the versioned request's options.
    assert [%{name: "TOKEN", status: :resolved}] = SecretSpec.report!(builder).secrets
  end

  test "scope is selected and returned", %{tmp_dir: dir} do
    builder =
      dir
      |> project("DATABASE_URL=postgres://db\nSENTRY_DSN=https://sentry\n")
      |> SecretSpec.with_scope("database")

    resolved = SecretSpec.load!(builder)
    assert resolved.scope == "database"
    assert Map.keys(resolved.secrets) == ["DATABASE_URL"]

    report = SecretSpec.report!(builder)
    assert report.scope == "database"
    assert Enum.map(report.secrets, & &1.name) == ["DATABASE_URL"]
  end

  test "set_as_env exports resolved secrets", %{tmp_dir: dir} do
    System.delete_env("DATABASE_URL")
    on_exit(fn -> System.delete_env("DATABASE_URL") end)

    dir
    |> project("DATABASE_URL=postgres://db\n")
    |> SecretSpec.load!()
    |> SecretSpec.Resolved.set_as_env()

    assert System.get_env("DATABASE_URL") == "postgres://db"
  end

  test "missing required secret is a typed error", %{tmp_dir: dir} do
    builder = project(dir, "")

    assert {:error, %MissingRequiredError{missing: missing}} = SecretSpec.load(builder)
    assert "DATABASE_URL" in missing
    assert_raise MissingRequiredError, fn -> SecretSpec.load!(builder) end

    # A report describes the gap instead of failing.
    report = SecretSpec.report!(builder)

    assert %{status: :missing_required, required: true} =
             Enum.find(report.secrets, &(&1.name == "DATABASE_URL"))
  end

  test "as_path returns a readable file", %{tmp_dir: dir} do
    manifest = """
    [project]
    name = "ex-test"
    revision = "1.0"

    [profiles.default]
    TLS_CERT = { description = "cert", required = true, as_path = true }
    """

    resolved = dir |> project("TLS_CERT=----cert-bytes----\n", manifest) |> SecretSpec.load!()

    try do
      cert = resolved.secrets["TLS_CERT"]
      assert cert.as_path
      assert cert.value == nil
      assert File.read!(ResolvedSecret.get(cert)) == "----cert-bytes----"
    after
      # as_path materializes a 0400 temp file the caller owns.
      :ok = SecretSpec.Resolved.close(resolved)
    end
  end

  test "an invalid manifest is a SecretSpec.Error" do
    result =
      SecretSpec.builder()
      |> SecretSpec.with_path("/definitely/does/not/exist/secretspec.toml")
      |> SecretSpec.with_reason("ex test")
      |> SecretSpec.load()

    assert {:error, %Error{kind: kind}} = result
    assert kind != ""
  end

  test "nil options are ignored" do
    builder =
      SecretSpec.builder()
      |> SecretSpec.with_path(nil)
      |> SecretSpec.with_provider(nil)
      |> SecretSpec.with_profile(nil)
      |> SecretSpec.with_scope(nil)
      |> SecretSpec.with_reason(nil)
      |> SecretSpec.with_caller(nil)
      |> SecretSpec.with_no_values(nil)

    assert builder == SecretSpec.builder()
  end

  test "keyword options match the pipeline" do
    caller = %CallerContext{name: "git"}

    assert SecretSpec.builder(profile: "prod", reason: "boot", caller: caller, no_values: true) ==
             SecretSpec.builder()
             |> SecretSpec.with_profile("prod")
             |> SecretSpec.with_reason("boot")
             |> SecretSpec.with_caller(caller)
             |> SecretSpec.with_no_values()

    assert_raise ArgumentError, fn -> SecretSpec.builder(profle: "prod") end
  end
end
