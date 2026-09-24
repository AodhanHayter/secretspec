defmodule SecretSpec.SecretReport do
  @moduledoc """
  Value-free resolution outcome for one declared secret: how it would resolve
  and from where, never the value itself.

  `status` is `:resolved`, `:missing_required`, or `:missing_optional`.
  """
  defstruct [
    :name,
    :status,
    :source_provider,
    required: false,
    default_applied: false,
    generated: false,
    as_path: false
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          status: :resolved | :missing_required | :missing_optional,
          required: boolean(),
          source_provider: String.t() | nil,
          default_applied: boolean(),
          generated: boolean(),
          as_path: boolean()
        }
end

defmodule SecretSpec.Report do
  @moduledoc """
  A value-free resolution snapshot. Unlike `SecretSpec.Resolved`, a missing
  required secret is a `:missing_required` status here, not an error.
  """
  defstruct [:provider, :profile, :scope, secrets: []]

  @type t :: %__MODULE__{
          provider: String.t(),
          profile: String.t(),
          scope: String.t() | nil,
          secrets: [SecretSpec.SecretReport.t()]
        }
end
