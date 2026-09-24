defmodule SecretSpec.ConformanceTest do
  # Cross-language conformance: resolve the shared fixtures and assert this SDK
  # produces the canonical result every other SDK must also produce.
  use ExUnit.Case, async: true

  alias SecretSpec.Resolved

  @fixtures Path.expand("../../conformance/fixtures", __DIR__)

  defp builder(dir) do
    SecretSpec.builder()
    |> SecretSpec.with_path(Path.join(dir, "secretspec.toml"))
    |> SecretSpec.with_provider("dotenv://" <> Path.join(dir, ".env"))
    |> SecretSpec.with_reason("conformance")
  end

  defp expected(dir, file), do: dir |> Path.join(file) |> File.read!() |> JSON.decode!()

  defp canonical(%Resolved{} = r) do
    %{
      "profile" => r.profile,
      "secrets" =>
        Map.new(r.secrets, fn {name, s} ->
          value = if s.as_path, do: File.read!(s.path), else: s.value

          {name,
           %{"value" => value, "source" => Atom.to_string(s.source), "as_path" => s.as_path}}
        end),
      "missing_required" => [],
      "missing_optional" => Enum.sort(r.missing_optional)
    }
  end

  defp canonical_report(report) do
    %{
      "profile" => report.profile,
      "secrets" =>
        Map.new(report.secrets, fn s ->
          {s.name,
           %{
             "status" => Atom.to_string(s.status),
             "required" => s.required,
             "as_path" => s.as_path,
             "generated" => s.generated,
             "default_applied" => s.default_applied,
             # Present-or-not, not the path-dependent value.
             "source_provider" => s.source_provider != nil
           }}
        end)
    }
  end

  for fixture <- @fixtures |> File.ls!() |> Enum.sort(),
      File.dir?(Path.join(@fixtures, fixture)) do
    @dir Path.join(@fixtures, fixture)

    test "#{fixture}: resolve" do
      resolved = SecretSpec.load!(builder(@dir))

      try do
        assert canonical(resolved) == expected(@dir, "expected.json")
      after
        Resolved.close(resolved)
      end
    end

    test "#{fixture}: no_values fields are all null" do
      resolved = @dir |> builder() |> SecretSpec.with_no_values() |> SecretSpec.load!()

      try do
        assert Resolved.fields(resolved) == expected(@dir, "expected_no_values.json")
      after
        Resolved.close(resolved)
      end
    end

    test "#{fixture}: report" do
      assert canonical_report(SecretSpec.report!(builder(@dir))) ==
               expected(@dir, "expected_report.json")
    end
  end
end
