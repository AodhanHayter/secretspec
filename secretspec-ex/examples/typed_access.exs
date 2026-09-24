# Generate the typed struct into your project first:
#
#   secretspec schema | npx quicktype -s schema --top-level AppSecrets --lang elixir -o lib/app_secrets.ex
resolved = SecretSpec.builder() |> SecretSpec.with_reason("typed access") |> SecretSpec.load!()
typed = AppSecrets.from_map(SecretSpec.Resolved.fields(resolved))
# A typed String.t()
IO.puts(typed.database_url)
