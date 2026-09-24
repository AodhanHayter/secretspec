defmodule SecretSpec.ResolvedSecret do
  @moduledoc "One resolved secret. Exactly one of `value` / `path` is set."
  defstruct [:value, :path, :source, :source_provider, as_path: false]

  @type t :: %__MODULE__{
          value: String.t() | nil,
          path: String.t() | nil,
          as_path: boolean(),
          source: :provider | :generated | :default | nil,
          source_provider: String.t() | nil
        }

  @doc "The usable string: the file path for `as_path` secrets, else the value."
  @spec get(t()) :: String.t() | nil
  def get(%__MODULE__{as_path: true, path: path}), do: path
  def get(%__MODULE__{value: value}), do: value
end

defmodule SecretSpec.Resolved do
  @moduledoc "A successful resolution, mirroring the Rust `Resolved` wrapper."
  alias SecretSpec.ResolvedSecret

  defstruct [:provider, :profile, :scope, secrets: %{}, missing_optional: []]

  @type t :: %__MODULE__{
          provider: String.t(),
          profile: String.t(),
          scope: String.t() | nil,
          secrets: %{String.t() => ResolvedSecret.t()},
          missing_optional: [String.t()]
        }

  @doc "Export each resolved secret into the OS environment by its declared name."
  @spec set_as_env(t()) :: :ok
  def set_as_env(%__MODULE__{secrets: secrets}) do
    for {name, secret} <- secrets,
        usable = ResolvedSecret.get(secret),
        do: System.put_env(name, usable)

    :ok
  end

  @doc """
  Flat `%{SECRET_NAME => value}` map (the file path for `as_path`).

  A secret with no usable value (e.g. under `no_values`) maps to `nil`. This is
  the input for a quicktype-generated decoder; see `secretspec schema`.
  """
  @spec fields(t()) :: %{String.t() => String.t() | nil}
  def fields(%__MODULE__{secrets: secrets}),
    do: Map.new(secrets, fn {name, secret} -> {name, ResolvedSecret.get(secret)} end)

  @doc """
  Remove the temp files backing any `as_path` secrets in this result.

  The resolver persists those files (mode 0400) so their paths stay valid after
  resolution; the caller owns their lifetime. A file already gone is not an
  error. Every file is attempted even if one cannot be removed; the first
  failure is returned once the rest have been cleaned up.
  """
  @spec close(t()) :: :ok | {:error, %File.Error{}}
  def close(%__MODULE__{secrets: secrets}) do
    secrets
    |> Map.values()
    |> Enum.filter(&(&1.as_path and &1.path))
    |> Enum.reduce(:ok, fn %{path: path}, acc ->
      case File.rm(path) do
        result when result == :ok or result == {:error, :enoent} ->
          acc

        {:error, reason} when acc == :ok ->
          {:error, %File.Error{reason: reason, action: "remove file", path: path}}

        {:error, _} ->
          acc
      end
    end)
  end
end
