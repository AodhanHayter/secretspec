defmodule SecretSpec.CloseTest do
  # `Resolved.close/1` must attempt every as_path file: stopping at the first
  # file the OS refuses to remove would strand every later secret on disk.
  # Matches the Go (firstErr), .NET (firstError), and Python SDKs.
  use ExUnit.Case, async: true

  alias SecretSpec.{Resolved, ResolvedSecret}

  @moduletag :tmp_dir

  defp resolved(paths) do
    secrets =
      paths
      |> Enum.with_index()
      |> Map.new(fn {path, i} ->
        File.write!(path, "super-secret-value")

        {"S#{i}",
         %ResolvedSecret{path: path, as_path: true, source: :provider, source_provider: "dotenv"}}
      end)

    %Resolved{provider: "dotenv", profile: "default", secrets: secrets}
  end

  test "removes every as_path file", %{tmp_dir: dir} do
    paths = for i <- 0..2, do: Path.join(dir, "secret#{i}")
    assert :ok = Resolved.close(resolved(paths))
    refute Enum.any?(paths, &File.exists?/1)
  end

  test "is idempotent", %{tmp_dir: dir} do
    r = resolved([Path.join(dir, "secret")])
    assert :ok = Resolved.close(r)
    assert :ok = Resolved.close(r)
  end

  test "removes the rest when one file cannot be removed", %{tmp_dir: dir} do
    # Removing a file needs write permission on its directory.
    locked = Path.join(dir, "locked")
    File.mkdir_p!(locked)
    blocked = Path.join(locked, "secret")
    paths = [Path.join(dir, "a"), blocked, Path.join(dir, "b")]
    r = resolved(paths)
    File.chmod!(locked, 0o500)
    on_exit(fn -> File.chmod(locked, 0o700) end)

    assert {:error, %File.Error{path: ^blocked, reason: :eacces}} = Resolved.close(r)
    assert File.exists?(blocked)
    refute File.exists?(Path.join(dir, "a"))
    refute File.exists?(Path.join(dir, "b"))
  end
end
