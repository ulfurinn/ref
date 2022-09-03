defmodule Ulfnet.Ref do
  alias Ulfnet.Ref.Table

  @tag __MODULE__
  @type ref() :: {Ulfnet.Ref, reference(), reference()}

  defguard is_cell_ref(ref) when is_tuple(ref) and tuple_size(ref) == 3 and elem(ref, 0) == @tag and is_reference(elem(ref, 1)) and is_reference(elem(ref, 2))
  defguard is_cell(item) when is_map(item) and is_cell_ref(:erlang.map_get(Ulfnet.Ref, item))

  defdelegate new(), to: Table
  defdelegate ref(item), to: Table
  defdelegate make_ref(table), to: Table
  defdelegate make_ref(item, table), to: Table
  defdelegate put(table, item), to: Table
  defdelegate update(table, ref, fun), to: Table
  defdelegate get(table, item), to: Table
  defdelegate delete(table, ref), to: Table
  defdelegate root(table, item), to: Table
  defdelegate unroot(table, item), to: Table

  def put(item = %{@tag => {@tag, table, _}}), do: put(table, item)
  def update(ref = {@tag, table, _}, fun), do: update(table, ref, fun)
  def get(ref = {@tag, table, _}), do: get(table, ref)
  def delete(ref = {@tag, table, _}), do: delete(table, ref)
  def delete(%{@tag => ref = {@tag, table, _}}), do: delete(table, ref)
  def root(ref = {@tag, table, _}), do: root(table, ref)
  def root(%{@tag => ref = {@tag, table, _}}), do: root(table, ref)
  def unroot(ref = {@tag, table, _}), do: unroot(table, ref)
  def unroot(%{@tag => ref = {@tag, table, _}}), do: unroot(table, ref)

end
