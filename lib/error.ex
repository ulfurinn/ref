defmodule Ulfnet.Ref.ReferencedCellNotInTable do
  defexception [:message]

  @impl true
  def exception(_), do: %__MODULE__{message: "referenced cell not in table"}
end

defmodule Ulfnet.Ref.NotReferenceable do
  defexception [:message]

  @impl true
  def exception(_), do: %__MODULE__{message: "not a referenceable term"}
end

defmodule Ulfnet.Ref.CannotDeleteReferenced do
  defexception [:message]

  @impl true
  def exception(_), do: %__MODULE__{message: "cannot delete an item being referenced"}
end
