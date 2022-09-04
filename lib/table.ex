defmodule Ulfnet.Ref.Table do
  @moduledoc false

  @tag Ulfnet.Ref

  def new() do
    :ets.new(__MODULE__, [:set, :public])
  end

  def put(table, item = %{@tag => {@tag, table, ref}}) when is_reference(table) and is_reference(ref) do
    :ets.insert(table, {ref, item})
    update_item_links(table, item)
    item
  end

  def root(table, %{@tag => ref}) when is_reference(table), do: root(table, ref)
  def root(table, {@tag, table, ref}) when is_reference(table) and is_reference(ref) do
    ets_update(table, :roots, MapSet.new([ref]), &MapSet.put(&1, ref))
  end

  def root(table, %{@tag => ref}) when is_reference(table), do: root(table, ref)
  def unroot(table, {@tag, table, ref}) when is_reference(table) and is_reference(ref) do
    # TODO: trigger gc if the unrooted item was without inlinks?
    ets_update(table, :roots, MapSet.new(), &MapSet.delete(&1, ref))
  end

  def get(table, r = {@tag, table, ref}) when is_reference(table) and is_reference(ref) do
    get_int(table, r)
  end

  defp get_int(table, {@tag, table, ref}) when is_reference(table) and is_reference(ref) do
    get_int(table, ref)
  end
  defp get_int(table, ref) when is_reference(table) and is_reference(ref) do
    ets_fetch(table, ref)
  end

  def update(table, {@tag, table, ref}, fun) when is_reference(table) and is_reference(ref) and is_function(fun, 1) do
    put(table, fun.(get_int(table, ref)))
  end

  def delete(table, {@tag, table, ref}) when is_reference(table) and is_reference(ref), do: delete(table, ref)
  def delete(table, ref) when is_reference(table) and is_reference(ref) do
    current_inlinks = inlinks(table, ref)
    if MapSet.size(current_inlinks) > 0 do
      raise Ulfnet.Ref.CannotDeleteReferenced
    end

    ets_delete(table, ref)
    |> process_outlinks(ref, outlinks(table, ref), MapSet.new())

    nil
  end

  defp gc(table, ref) when is_reference(table) and is_reference(ref) do
    unless MapSet.member?(roots(table), ref) do
      delete(table, ref)
    end
    table
  end

  def ref(%{@tag => ref}), do: ref

  def ref!(%{@tag => ref = {@tag, _, internal_ref}}) when is_reference(internal_ref), do: ref
  def ref!(_), do: raise Ulfnet.Ref.NotReferenceable

  def internal_ref(%{@tag => {@tag, _, ref}}), do: ref

  def make_ref(table) when is_reference(table), do: {@tag, table, Kernel.make_ref()}

  def make_ref(item = %{@tag => nil}, table) when is_reference(table), do: Map.put(item, @tag, make_ref(table))
  def make_ref(item = %{@tag => _}, table) when is_reference(table), do: item

  defp update_item_links(table, item = %{@tag => {@tag, table, ref}}) do
    process_outlinks(table, ref, outlinks(table, ref), scan_outlinks(item))
  end

  defp process_outlinks(table, ref, old_outlinks, new_outlinks) do
    table
    |> ensure_refs_in_table(new_outlinks)
    |> process_added_outlinks(ref, MapSet.difference(new_outlinks, old_outlinks))
    |> process_removed_outlinks(ref, MapSet.difference(old_outlinks, new_outlinks))
    |> store_outlinks(ref, new_outlinks)
  end

  defp ensure_refs_in_table(table, refs) do
    if Enum.any?(refs, fn ref -> ! ets_has_key?(table, ref) end), do: raise Ulfnet.Ref.ReferencedCellNotInTable
    table
  end

  defp process_added_outlinks(table, ref, outlinks) do
    outlinks |> Enum.reduce(table, fn linked_ref, table ->
      item_inlinks = inlinks(table, linked_ref)
      item_inlinks = MapSet.put(item_inlinks, ref)
      store_inlinks(table, linked_ref, item_inlinks)
    end)
  end

  defp process_removed_outlinks(table, ref, outlinks) do
    outlinks |> Enum.reduce(table, fn linked_ref, table ->
      item_inlinks = inlinks(table, linked_ref)
      item_inlinks = MapSet.delete(item_inlinks, ref)
      store_inlinks(table, linked_ref, item_inlinks)
      |> maybe_gc(linked_ref, item_inlinks)
    end)
  end

  defp scan_outlinks(item = %{@tag => {@tag, table, ref}}), do: scan_outlinks(Map.delete(item, @tag), table, ref, MapSet.new())

  # struct don't implement Enumerable
  defp scan_outlinks(value = %{__struct__: _}, table, self_ref, acc), do: scan_outlinks(Map.delete(value, :__struct__), table, self_ref, acc)

  # descend into each value
  defp scan_outlinks(value = %{}, table, self_ref, acc) do
    value |> Enum.reduce(acc, fn {_, value}, acc ->
      scan_outlinks(value, table, self_ref, acc)
    end)
  end

  # descend into each element
  defp scan_outlinks(value, table, self_ref, acc) when is_list(value) do
    value |> Enum.reduce(acc, fn value, acc ->
      scan_outlinks(value, table, self_ref, acc)
    end)
  end

  # circular ref – do not include
  defp scan_outlinks({@tag, table, self_ref}, table, self_ref, acc), do: acc

  # ref to another item
  defp scan_outlinks({@tag, table, ref}, table, _, acc) when is_reference(ref) do
    MapSet.put(acc, ref)
  end

  # descend into each element
  defp scan_outlinks(value, table, self_ref, acc) when is_tuple(value), do: scan_outlinks(Tuple.to_list(value), table, self_ref, acc)

  # anything else
  defp scan_outlinks(_, _, _, acc), do: acc

  defp maybe_gc(table, ref, links) do
    if MapSet.size(links) == 0, do: gc(table, ref), else: table
  end

  defp roots(table), do: ets_fetch(table, :roots, MapSet.new())

  def inlinks(table, ref), do: ets_fetch(table, {:inlinks, ref}, MapSet.new())
  def outlinks(table, ref), do: ets_fetch(table, {:outlinks, ref}, MapSet.new())

  defp store_inlinks(table, ref, links) when map_size(links) == 0 do
    :ets.delete(table, {:inlinks, ref})
    table
  end
  defp store_inlinks(table, ref, links) do
    :ets.insert(table, {{:inlinks, ref}, links})
    table
  end

  defp store_outlinks(table, ref, links) when map_size(links) == 0 do
    :ets.delete(table, {:outlinks, ref})
    table
  end
  defp store_outlinks(table, ref, links) do
    :ets.insert(table, {{:outlinks, ref}, links})
    table
  end

  defp ets_fetch(table, key) do
    [{^key, value}] = :ets.lookup(table, key)
    value
  end

  defp ets_fetch(table, key, default) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      _ -> if is_function(default), do: default.(), else: default
    end
  end

  def ets_has_key?(table, key) do
    :ets.member(table, key)
  end

  defp ets_update(table, key, default, fun) do
    case :ets.lookup(table, key) do
      [{^key, value}] ->
        :ets.insert(table, {key, fun.(value)})
      _ ->
        :ets.insert(table, {key, default})
    end
    table
  end

  defp ets_delete(table, key) do
    :ets.delete(table, key)
    table
  end

  def cells(table) do
    :ets.foldl(fn element, list ->
      case element do
        {ref, item} when is_reference(ref) -> [item | list]
        _ -> list
      end
    end, [], table)
  end
end

