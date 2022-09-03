defmodule Ulfnet.Ref.Table do
  import Kernel, except: [make_ref: 0]

  defstruct [
    refs: %{},
    outlinks: %{},
    inlinks: %{},
    roots: %{},
  ]

  @tag Ulfnet.Ref

  @type ref() :: {Ulfnet.Ref, reference()}

  defguard is_cell_ref(ref) when is_tuple(ref) and tuple_size(ref) == 2 and elem(ref, 0) == @tag and is_reference(elem(ref, 1))
  defguard is_cell(item) when is_map(item) and is_cell_ref(:erlang.map_get(Ulfnet.Ref, item))

  def new() do
    %__MODULE__{}
  end

  def check_in(table = %__MODULE__{}, item = %{@tag => nil}) do
    check_in(table, make_ref(), item)
  end
  def check_in(table = %__MODULE__{}, ref, item = %{@tag => nil}) do
    item = Map.put(item, @tag, ref)
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
  def unroot(table = %__MODULE__{roots: roots}, %{@tag => {@tag, ref}}) when is_reference(ref) do
    %__MODULE__{table | roots: Map.delete(roots, ref)}
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

    %__MODULE__{table | refs: Map.delete(refs, ref)}
    |> process_outlinks(ref, outlinks, [])
  end

  defp gc(table = %__MODULE__{roots: roots}, ref) when is_reference(ref) do
    case roots do
      %{^ref => _} -> table
      _ -> delete(table, ref)
    end
  end

  def ref(%{@tag => ref}), do: ref

  def ref!(%{@tag => ref = {@tag, internal_ref}}) when is_reference(internal_ref), do: ref
  def ref!(_), do: raise "not a referenceable term"

  def internal_ref(%{@tag => {@tag, ref}}), do: ref

  def make_ref(), do: {@tag, Kernel.make_ref()}
  def make_ref(item = %{@tag => nil}), do: Map.put(item, @tag, make_ref())
  def make_ref(item = %{@tag => _}), do: item

  defp update_item_links(table, item = %{@tag => {@tag, ref}}) do
    process_outlinks(table, ref, Map.get(table.outlinks, ref, []), scan_outlinks(item))
  end

  defp process_outlinks(table, ref, old_outlinks, new_outlinks) do
    table
    |> ensure_refs_in_table(new_outlinks)
    |> process_added_outlinks(ref, new_outlinks -- old_outlinks)
    |> process_removed_outlinks(ref, old_outlinks -- new_outlinks)
    |> set_outlink_element(ref, new_outlinks)
  end

  defp ensure_refs_in_table(table = %__MODULE__{refs: refs}, links) do
    missing_refs = Enum.reject(links, &Map.has_key?(refs, &1))
    if missing_refs != [], do: raise "referenced cell not in table"
    table
  end

  defp process_added_outlinks(table, ref, outlinks) do
    outlinks |> Enum.reduce(table, fn linked_ref, table ->
      inlinks = Map.update(table.inlinks, linked_ref, [ref], &[ref | &1])
      %__MODULE__{table | inlinks: inlinks}
    end)
  end

  defp process_removed_outlinks(table, ref, outlinks) do
    outlinks |> Enum.reduce(table, fn linked_ref, table ->
      item_inlinks = Map.get(table.inlinks, linked_ref, []) -- [ref]
      set_inlink_element_with_gc(table, linked_ref, item_inlinks)
    end)
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

  defp set_inlink_element_with_gc(table , ref, []) do
    table |> set_inlink_element(ref, []) |> gc(ref)
  end
  defp set_inlink_element_with_gc(table , ref, list) do
    table |> set_inlink_element(ref, list)
  end

  defp set_inlink_element(table = %__MODULE__{inlinks: inlinks}, ref, []) do
    %__MODULE__{table | inlinks: Map.delete(inlinks, ref)}
  end
  defp set_inlink_element(table = %__MODULE__{inlinks: inlinks}, ref, list) do
    %__MODULE__{table | inlinks: Map.put(inlinks, ref, list)}
  end

  defp set_outlink_element(table = %__MODULE__{outlinks: outlinks}, ref, []) do
    %__MODULE__{table | outlinks: Map.delete(outlinks, ref)}
  end
  defp set_outlink_element(table = %__MODULE__{outlinks: outlinks}, ref, list) do
    %__MODULE__{table | outlinks: Map.put(outlinks, ref, list)}
  end
end

