defmodule SecretSpec do
  @moduledoc """
  SecretSpec Elixir SDK (0.22+).

  A thin client over a Rustler NIF that calls the SecretSpec Rust resolver
  directly. Resolution (providers, chains, profiles, generation, `as_path`)
  happens entirely in the Rust core; this module marshals a JSON request,
  parses the response envelope, and exposes it with the same vocabulary as the
  Rust derive crate.

      {:ok, resolved} =
        SecretSpec.builder()
        |> SecretSpec.with_provider("keyring://")
        |> SecretSpec.with_reason("boot")
        |> SecretSpec.load()

      SecretSpec.ResolvedSecret.get(resolved.secrets["DATABASE_URL"])

  Every `with_*` function ignores `nil`, so optional settings can be piped
  through unconditionally. `builder/1` also accepts the same settings as
  keyword options:

      SecretSpec.builder(profile: "production", reason: "boot") |> SecretSpec.load!()
  """

  alias SecretSpec.{
    CallerContext,
    Error,
    MissingRequiredError,
    Native,
    Report,
    Resolved,
    ResolvedSecret,
    SecretReport
  }

  # Response wire-format version this SDK understands. Tracks libsecretspec's
  # RESOLVE_SCHEMA_VERSION.
  @resolve_schema_version 2
  # Tracks secretspec's RESOLUTION_REPORT_SCHEMA_VERSION.
  @report_schema_version 1

  @statuses [:resolved, :missing_required, :missing_optional]
  @sources [:provider, :generated, :default]
  @builder_options [:path, :provider, :profile, :scope, :reason, :caller, :no_values]

  defstruct request: %{}, inline: nil

  @opaque t :: %__MODULE__{}

  @doc """
  Start a resolution request, mirroring the derive crate's `SecretSpec::builder()`.

  `opts` may set any of #{Enum.map_join(@builder_options, ", ", &"`:#{&1}`")}; each
  is applied with the matching `with_*` function. Unknown keys raise
  `ArgumentError`.
  """
  @spec builder(keyword()) :: t()
  def builder(opts \\ []) do
    opts
    |> Keyword.validate!(@builder_options)
    |> Enum.reduce(%__MODULE__{}, fn {key, value}, b ->
      apply(__MODULE__, :"with_#{key}", [b, value])
    end)
  end

  @doc "Resolve the manifest at `path` instead of searching from the working directory."
  @spec with_path(t(), Path.t() | nil) :: t()
  def with_path(builder, nil), do: builder
  def with_path(%__MODULE__{} = b, path), do: %{b | inline: nil} |> put("path", path)

  @doc """
  Resolve an inline-spec v2 map at `base_dir` (SecretSpec 0.21+).

  `base_dir` resolves relative provider paths and `project.extends`.
  """
  @spec with_inline_spec(t(), map(), Path.t()) :: t()
  def with_inline_spec(%__MODULE__{} = b, spec, base_dir)
      when is_map(spec) and is_binary(base_dir),
      do: %{b | request: Map.delete(b.request, "path"), inline: {spec, base_dir}}

  @doc "Use the provider URI or alias `provider`, for example `\"keyring://\"`."
  @spec with_provider(t(), String.t() | nil) :: t()
  def with_provider(b, provider), do: put(b, "provider", provider)

  @doc "Resolve with the manifest profile `profile`."
  @spec with_profile(t(), String.t() | nil) :: t()
  def with_profile(b, profile), do: put(b, "profile", profile)

  @doc "Limit resolution to a named manifest scope (SecretSpec 0.17+)."
  @spec with_scope(t(), String.t() | nil) :: t()
  def with_scope(b, scope), do: put(b, "scope", scope)

  @doc "Record why the secrets are accessed, for `require_reason` policies and audit records."
  @spec with_reason(t(), String.t() | nil) :: t()
  def with_reason(b, reason), do: put(b, "reason", reason)

  @doc "Identify the invoking software integration (SecretSpec 0.20+)."
  @spec with_caller(t(), CallerContext.t() | nil) :: t()
  def with_caller(b, nil), do: b

  def with_caller(b, %CallerContext{} = caller),
    do: put(b, "caller", CallerContext.to_request(caller))

  @doc "Omit secret values, returning only structure and provenance."
  @spec with_no_values(t(), boolean() | nil) :: t()
  def with_no_values(b, no_values \\ true)
  def with_no_values(b, nil), do: b

  def with_no_values(b, no_values) when is_boolean(no_values),
    do: put(b, "no_values", no_values)

  defp put(b, _key, nil), do: b
  defp put(%__MODULE__{} = b, key, value), do: %{b | request: Map.put(b.request, key, value)}

  @doc """
  Resolve secrets.

  Returns `{:error, %SecretSpec.MissingRequiredError{}}` if a required secret
  is missing and `{:error, %SecretSpec.Error{}}` for any other failure.
  """
  @spec load(t()) :: {:ok, Resolved.t()} | {:error, Error.t() | MissingRequiredError.t()}
  def load(%__MODULE__{} = b) do
    with {:ok, response} <- checked_response(b, nil, @resolve_schema_version) do
      case response["missing_required"] || [] do
        [] ->
          {:ok,
           %Resolved{
             provider: response["provider"],
             profile: response["profile"],
             scope: response["scope"],
             missing_optional: response["missing_optional"] || [],
             secrets:
               Map.new(response["secrets"] || %{}, fn {name, s} -> {name, resolved_secret(s)} end)
           }}

        missing ->
          {:error, %MissingRequiredError{missing: missing}}
      end
    end
  rescue
    # Raised by enum!/2 for a value this SDK does not know.
    e in Error -> {:error, e}
  end

  @doc "Like `load/1`, but raises on error."
  @spec load!(t()) :: Resolved.t()
  def load!(b), do: unwrap!(load(b))

  @doc """
  Resolve a value-free `SecretSpec.Report` (the inventory/preflight view).

  Unlike `load/1`, a missing required secret is not an error: it appears as a
  `SecretSpec.SecretReport` with status `"missing_required"`.
  """
  @spec report(t()) :: {:ok, Report.t()} | {:error, Error.t()}
  def report(%__MODULE__{} = b) do
    with {:ok, response} <- checked_response(b, "report", @report_schema_version) do
      {:ok,
       %Report{
         provider: response["provider"],
         profile: response["profile"],
         scope: response["scope"],
         secrets: Enum.map(response["secrets"] || [], &secret_report/1)
       }}
    end
  rescue
    e in Error -> {:error, e}
  end

  @doc "Like `report/1`, but raises on error."
  @spec report!(t()) :: Report.t()
  def report!(b), do: unwrap!(report(b))

  @doc "The version reported by the embedded resolver NIF."
  @spec abi_version() :: String.t()
  def abi_version, do: Native.abi_version()

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: raise(error)

  defp checked_response(%__MODULE__{request: request, inline: inline}, mode, expected_version) do
    options = if mode, do: Map.put(request, "mode", mode), else: request
    default_sigchld()

    raw =
      case inline do
        nil ->
          Native.resolve(JSON.encode!(options))

        {spec, base_dir} ->
          Native.call(
            JSON.encode!(%{
              "request_version" => 1,
              "operation" => "resolve",
              "source" => %{
                "kind" => "inline",
                "spec_version" => 2,
                "base_dir" => base_dir,
                "spec" => spec
              },
              "options" => options
            })
          )
      end

    case JSON.decode!(raw) do
      %{"ok" => true, "response" => %{"schema_version" => ^expected_version} = response} ->
        {:ok, response}

      %{"ok" => true, "response" => %{"schema_version" => version}} ->
        kind = mode || "resolve"

        {:error,
         %Error{
           kind: "version",
           message:
             "unsupported #{kind} schema version #{inspect(version)} (expected #{expected_version}); " <>
               "the libsecretspec library and this SDK are out of sync"
         }}

      %{"ok" => true} ->
        {:error, %Error{kind: "ffi", message: "secretspec_resolve reported ok with no response"}}

      envelope ->
        error = envelope["error"] || %{}
        {:error, %Error{kind: error["kind"] || "unknown", message: error["message"] || ""}}
    end
  end

  # The BEAM ignores SIGCHLD, so the kernel reaps provider CLIs (op, pass,
  # lpass, ...) before Rust can wait on them: "No child processes". Restore the
  # OS default. BEAM ports are unaffected (erl_child_setup reaps them), and it
  # is never flipped back, so concurrent calls cannot race. Windows has no
  # SIGCHLD.
  defp default_sigchld do
    with {:unix, _} <- :os.type(), do: :os.set_signal(:sigchld, :default)
  end

  defp resolved_secret(s) do
    %ResolvedSecret{
      value: s["value"],
      path: s["path"],
      as_path: s["as_path"] || false,
      source: enum!(s["source"], @sources),
      source_provider: s["source_provider"]
    }
  end

  defp secret_report(s) do
    %SecretReport{
      name: s["name"],
      status: enum!(s["status"], @statuses),
      required: s["required"] || false,
      source_provider: s["source_provider"],
      default_applied: s["default_applied"] || false,
      generated: s["generated"] || false,
      as_path: s["as_path"] || false
    }
  end

  # Map a wire string onto a known atom without creating atoms from input.
  defp enum!(nil, _allowed), do: nil

  defp enum!(value, allowed) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise Error,
        kind: "version",
        message:
          "unknown value #{inspect(value)} (expected one of #{inspect(allowed)}); " <>
            "the libsecretspec library and this SDK are out of sync"
  end
end
