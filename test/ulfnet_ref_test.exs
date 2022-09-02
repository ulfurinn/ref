defmodule UlfnetRefTest do
  use ExUnit.Case
  alias Ulfnet.Ref.Table, as: RefTable
  doctest RefTable

  defmodule Data do
    defstruct [Ulfnet.Ref, :data]
  end

  test "put generated" do
    table = RefTable.new()
    {table, item} = RefTable.check_in(table, %Data{data: 1})

    ref = RefTable.ref(item)
    assert item == RefTable.get(table, ref)
  end

  test "put external" do
    ref = RefTable.make_ref()
    {table, _} = RefTable.new() |> RefTable.put(ref, %Data{data: 1})

    assert 1 == RefTable.get(table, ref).data
  end

  test "update" do
    ref = RefTable.make_ref()
    {table, _} = RefTable.new() |> RefTable.put(ref, %Data{data: 1})

    item = RefTable.get(table, ref)
    table = RefTable.put(table, %Data{item | data: 2})

    assert 2 == RefTable.get(table, ref).data
  end

  test "update fun" do
    ref = RefTable.make_ref()
    {table, _} = RefTable.new() |> RefTable.put(ref, %Data{data: 1})

    table = RefTable.update(table, ref, fn item = %Data{data: data} -> %Data{item | data: data + 1} end)

    assert 2 == RefTable.get(table, ref).data
  end

  test "link tracking" do
    item1 = RefTable.make_ref(%Data{})
    item2 = RefTable.make_ref(%Data{data: RefTable.ref(item1)})

    table = RefTable.new()
      |> RefTable.put(item1)
      |> RefTable.put(item2)

    assert item1 == RefTable.get(table, RefTable.ref(item1))
    assert item2 == RefTable.get(table, RefTable.ref(item2))

    assert 2 == map_size(table.refs)
    assert %{RefTable.internal_ref(item2) => [RefTable.internal_ref(item1)]} == table.outlinks
    assert %{RefTable.internal_ref(item1) => [RefTable.internal_ref(item2)]} == table.inlinks

    table = table |> RefTable.delete(RefTable.ref(item2))

    assert %{} == table.refs
    assert %{} == table.outlinks
    assert %{} == table.inlinks
  end
end
