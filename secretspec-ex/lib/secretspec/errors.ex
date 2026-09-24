defmodule SecretSpec.Error do
  @moduledoc """
  A resolution call failed (bad manifest, provider error, reason policy).

  `kind` is the stable error category reported by the resolver, for example
  `"io"`, `"invalid_request"`, or `"version"`.
  """
  defexception [:kind, :message]

  @type t :: %__MODULE__{kind: String.t(), message: String.t()}

  @impl true
  def message(%{kind: kind, message: message}), do: "#{message} (kind: #{kind})"
end

defmodule SecretSpec.MissingRequiredError do
  @moduledoc "One or more required secrets were not found anywhere."
  defexception [:missing]

  @type t :: %__MODULE__{missing: [String.t()]}

  @impl true
  def message(%{missing: missing}),
    do: "missing required secret(s): #{Enum.join(missing, ", ")} (kind: missing_required)"
end
