# Run from secretspec-ex/: mix run examples/scopes.exs
resolved = SecretSpec.builder() |> SecretSpec.with_scope("api") |> SecretSpec.load!()
IO.inspect(Map.keys(resolved.secrets), label: resolved.scope)
