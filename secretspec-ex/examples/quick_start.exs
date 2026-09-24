# Run from secretspec-ex/: mix run examples/quick_start.exs
resolved =
  SecretSpec.builder()
  |> SecretSpec.with_provider("keyring://")
  |> SecretSpec.with_profile("production")
  |> SecretSpec.with_reason("boot web app")
  |> SecretSpec.load!()

IO.puts("#{resolved.provider} #{resolved.profile}")
db = resolved.secrets["DATABASE_URL"]
# The value, or the file path for as_path secrets.
IO.puts(SecretSpec.ResolvedSecret.get(db))
# Export everything into the OS environment.
SecretSpec.Resolved.set_as_env(resolved)
