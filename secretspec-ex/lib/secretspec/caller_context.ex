defmodule SecretSpec.CallerContext do
  @moduledoc """
  Caller-asserted software-integration context (SecretSpec 0.20+).

  Unlike a reason, it never satisfies the `require_reason` policy.
  """
  @enforce_keys [:name]
  defstruct [:name, :version, :operation, :resource]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t() | nil,
          operation: String.t() | nil,
          resource: String.t() | nil
        }

  @doc false
  def to_request(%__MODULE__{} = caller) do
    caller |> Map.from_struct() |> Map.reject(fn {_, v} -> is_nil(v) end)
  end
end
