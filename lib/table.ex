defmodule Ulfnet.Ref.Table do
  import Kernel, except: [make_ref: 0]

  defstruct [
    refs: %{},
    outlinks: %{},
    inlinks: %{},
    roots: %{},
  ]

  @tag Ulfnet.Ref

  def new() do
    %__MODULE__{}
  end

  def check_in(table = %__MODULE__{}, item = %{@tag => nil}) do
    ref = make_ref()
    put(table, ref, item)
  end

  def put(table = %__MODULE__{refs: refs}, {@tag, ref}, item = %{@tag => nil}) when is_reference(ref) do
    if Map.get(refs, ref), do: raise ArgumentError, "reference already in use"

    item = %{item | @tag => {@tag, ref}}
    table = put(table, item)
    {table, item}
  end

  def put(table = %__MODULE__{refs: refs}, new = %{@tag => {@tag, ref}}) when is_reference(ref) do
    %__MODULE__{table | refs: Map.put(refs, ref, new)}
    |> update_item_links(new)
  end

  def root(table = %__MODULE__{roots: roots}, %{@tag => {@tag, ref}}) when is_reference(ref) do
    %__MODULE__{table | roots: Map.put(roots, ref, true)}
  end

  def get(table = %__MODULE__{}, r = {@tag, ref}) when is_reference(ref) do
    get_int(table, r)
  end

  defp get_int(table = %__MODULE__{}, ref) when is_reference(ref) do
    Map.get(table.refs, ref)
  end
  defp get_int(table = %__MODULE__{}, {@tag, ref}) when is_reference(ref) do
    get_int(table, ref)
  end

  def update(table = %__MODULE__{refs: refs}, {@tag, ref}, fun) when is_reference(ref) and is_function(fun, 1) do
    item = fun.(Map.fetch!(refs, ref))
    %__MODULE__{table | refs: Map.put(refs, ref, item)}
    |> update_item_links(item)
  end

  def delete(table = %__MODULE__{}, {@tag, ref}) when is_reference(ref), do: delete(table, ref)
  def delete(table = %__MODULE__{refs: refs, inlinks: inlinks}, ref) when is_reference(ref) do
    current_inlinks = Map.get(inlinks, ref, [])
    if current_inlinks != [] do
      raise "cannot delete item #{inspect ref}; inlinks = #{inspect inlinks}"
    end

    outlinks = Map.get(table.outlinks, ref, [])

    %__MODULE__{table | refs: Map.delete(refs, ref), inlinks: Map.delete(inlinks, ref)}
    |> process_outlinks(ref, outlinks, [])
  end

  def ref(%{@tag => ref}), do: ref

  def internal_ref(%{@tag => {@tag, ref}}), do: ref

  def make_ref(), do: {@tag, Kernel.make_ref()}
  def make_ref(item = %{@tag => nil}), do: Map.put(item, @tag, make_ref())

  defp update_item_links(table, item = %{@tag => {@tag, ref}}) do
    process_outlinks(table, ref, Map.get(table.outlinks, ref, []), scan_outlinks(item))
  end

  defp process_outlinks(table, ref, old_outlinks, new_outlinks) do
    added_links = new_outlinks -- old_outlinks
    table = added_links |> Enum.reduce(table, fn linked_ref, table ->
      inlinks = Map.update(table.inlinks, linked_ref, [ref], &[ref | &1])
      %__MODULE__{table | inlinks: inlinks}
    end)

    removed_links = old_outlinks -- new_outlinks
    table = removed_links |> Enum.reduce(table, fn linked_ref, table ->
      item_inlinks = Map.get(table.inlinks, linked_ref, []) -- [ref]
      if item_inlinks == [] do
        table
        |> set_inlink_element(linked_ref, [])
        |> delete(linked_ref)
      else
        set_inlink_element(table, linked_ref, item_inlinks)
      end
    end)

    outlinks = if new_outlinks == [] do
      Map.delete(table.outlinks, ref)
    else
      Map.put(table.outlinks, ref, new_outlinks)
    end
    %__MODULE__{table | outlinks: outlinks}
  end

  defp scan_outlinks(item = %{@tag => {@tag, ref}}), do: scan_outlinks(Map.delete(item, @tag), ref, %{}) |> Map.keys()

  # struct don't implement Enumerable
  defp scan_outlinks(value = %{__struct__: _}, self_ref, acc), do: scan_outlinks(Map.delete(value, :__struct__), self_ref, acc)

  # descend into each value
  defp scan_outlinks(value = %{}, self_ref, acc) do
    value |> Enum.reduce(acc, fn {_, value}, acc ->
      Map.merge(acc, scan_outlinks(value, self_ref, acc))
    end)
  end

  # descend into each element
  defp scan_outlinks(value, self_ref, acc) when is_list(value) do
    value |> Enum.reduce(acc, fn value, acc ->
      Map.merge(acc, scan_outlinks(value, self_ref, acc))
    end)
  end

  # circular ref – do not include
  defp scan_outlinks({@tag, self_ref}, self_ref, acc), do: acc

  # ref to another item
  defp scan_outlinks({@tag, ref}, _, acc) when is_reference(ref) do
    Map.put(acc, ref, true)
  end

  # descend into each element
  defp scan_outlinks(value, self_ref, acc) when is_tuple(value), do: scan_outlinks(Tuple.to_list(value), self_ref, acc)

  # anything else
  defp scan_outlinks(_, _, acc), do: acc

  defp set_inlink_element(table = %__MODULE__{inlinks: inlinks}, ref, list), do: %__MODULE__{table | inlinks: Map.put(inlinks, ref, list)}
end

