# secretspec (Elixir SDK, 0.22+)

Elixir bindings for [SecretSpec](https://secretspec.dev/), a declarative
secrets manager. This package is a thin client over a Rustler NIF that calls
`secretspec::resolve_json` directly: resolution (providers, chains, profiles,
generation, `as_path`) happens in the Rust core, so the SDK inherits every
provider with no Elixir-side logic. Requires Elixir 1.18+.

```elixir
# mix.exs
{:secretspec, "~> 0.22"}
```

```elixir
resolved =
  SecretSpec.builder()
  |> SecretSpec.with_provider("keyring://")
  |> SecretSpec.with_profile("production")
  |> SecretSpec.with_reason("boot web app")
  |> SecretSpec.load!()

db = resolved.secrets["DATABASE_URL"]
# The value, or the file path for as_path secrets.
SecretSpec.ResolvedSecret.get(db)
# Export everything into the OS environment.
SecretSpec.Resolved.set_as_env(resolved)
```

`SecretSpec.load/1` returns `{:ok, resolved}`, `{:error,
%SecretSpec.MissingRequiredError{}}` when a required secret is missing, or
`{:error, %SecretSpec.Error{}}` (with a stable `kind`) for any other failure.
`load!/1` raises instead.

`SecretSpec.builder/1` also takes the settings as keyword options:
`SecretSpec.builder(profile: "production", reason: "boot")`.

## Scopes

`SecretSpec.with_scope(builder, "api")` resolves only a named `[scopes.api]`
subset. Both `resolved.scope` and `report.scope` return the selected scope.

## Cleanup

`as_path` secrets are materialized to temp files that outlive the call. Call
`SecretSpec.Resolved.close(resolved)` when done so the secret files do not
accumulate.

## Value-free report

`SecretSpec.report/1` returns the inventory/preflight view: per-secret status
and provenance, never a value. A missing required secret appears as a
`SecretSpec.SecretReport` with status `:missing_required` instead of an error.

## Native library

The resolver is compiled into a Rustler NIF (`native/secretspec_nif`) that runs
on a dirty I/O scheduler. Released packages download a precompiled NIF through
RustlerPrecompiled. To build from source, depend on a checkout of the
SecretSpec repository (`{:secretspec, path: "path/to/secretspec/secretspec-ex"}`),
add `{:rustler, "~> 0.38"}` to your dependencies, and set
`SECRETSPEC_BUILD=1`. The NIF builds inside the repository's Cargo workspace,
so the Hex package alone cannot be built from source.

The NIF reads the VM's operating system environment, which `System.put_env/2`
does not change. Set `SECRETSPEC_*`, `env://` values, and CLI paths before the
VM starts, or use builder options. On Unix, the SDK sets `SIGCHLD` to the OS
default (`:os.set_signal(:sigchld, :default)`) so CLI-backed providers such as
1Password and `pass` can wait on their subprocesses.

## Development

From this directory, inside the repository's `devenv shell`:

```console
mix deps.get
mix test
```

In `dev` and `test` the NIF is always built from source. The codegen test runs
when `SECRETSPEC_BIN` points at a `secretspec` CLI build and `npx` is available.

See the [Elixir SDK documentation](https://secretspec.dev/sdk/elixir/).
