# The codegen test drives `secretspec schema` (SECRETSPEC_BIN, set by
# scripts/ci-sdks.sh) through quicktype (npx); skip it when either is missing.
exclude =
  if System.get_env("SECRETSPEC_BIN") && System.find_executable("npx"), do: [], else: [:codegen]

exclude = if match?({:unix, _}, :os.type()), do: exclude, else: [:unix | exclude]

ExUnit.start(exclude: exclude)
