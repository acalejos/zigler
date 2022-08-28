defmodule Zig.Type.Function do
  @behaviour Access

  defstruct [:name, :arity, :params, :return]
  alias Zig.Type

  @impl true
  defdelegate fetch(function, key), to: Map

  @type t :: %__MODULE__{
          name: atom(),
          arity: non_neg_integer(),
          params: [Type.t()],
          return: Type.t()
        }

  def from_json(%{"name" => name, "params" => params, "return" => return}) do
    params = Enum.map(params, &Type.from_json/1)

    arity =
      case params do
        [:env | rest] -> length(rest)
        _ -> length(params)
      end

    %__MODULE__{
      name: String.to_atom(name),
      arity: arity,
      params: params,
      return: Type.from_json(return)
    }
  end

  def marshalling_macros(%{params: params, return: return}) do
    list = [Type.marshal_zig(return) | Enum.map(params, &Type.marshal_elixir/1)]
    if Enum.any?(list), do: list, else: nil
  end
end
