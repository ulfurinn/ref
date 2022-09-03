defmodule UlfnetRefTest do
  use ExUnit.Case
  alias Ulfnet.Ref
  alias Ulfnet.Ref.Table
  doctest Ulfnet.Ref.Table

  defmodule Data do
    defstruct [Ulfnet.Ref, :data]
  end

  setup _ do
    {:ok, %{table: Ref.new()}}
  end

  test "put", %{table: table} do
    item = %Data{data: 1} |> Ref.make_ref(table)
    Ref.put(table, item)

    assert 1 == Ref.get(table, Ref.ref(item)).data
  end

  test "put twice", %{table: table} do
    item = %Data{data: 1} |> Ref.make_ref(table)
    Ref.put(table, item)
    ref = Ref.ref(item)

    item = Ref.get(table, ref)
    Ref.put(table, %Data{item | data: 2})

    assert 2 == Ref.get(table, ref).data
  end

  test "update fun", %{table: table} do
    item = %Data{data: 1} |> Ref.make_ref(table)
    Ref.put(table, item)
    ref = Ref.ref(item)

    Ref.update(table, ref, fn item = %Data{data: data} -> %Data{item | data: data + 1} end)

    assert 2 == Ref.get(table, ref).data
  end

  test "link tracking", %{table: table} do
    item1 = %Data{} |> Ref.make_ref(table)
    item2 = %Data{data: Ref.ref(item1)} |> Ref.make_ref(table)

    table
      |> Ref.put(item1)
      |> Ref.put(item2)

    assert item1 == Ref.get(table, Ref.ref(item1))
    assert item2 == Ref.get(table, Ref.ref(item2))

    assert 2 == length(Table.cells(table))
    assert MapSet.new([Table.internal_ref(item1)]) == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new([Table.internal_ref(item2)]) == Table.inlinks(table, Table.internal_ref(item1))

    table |> Ref.delete(Ref.ref(item2))

    assert 0 == length(Table.cells(table))
    assert MapSet.new() == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new() == Table.inlinks(table, Table.internal_ref(item1))
  end

  test "link tracking, two refs", %{table: table} do
    item1 = %Data{} |> Ref.make_ref(table)
    item2 = %Data{data: Ref.ref(item1)} |> Ref.make_ref(table)
    item3 = %Data{data: Ref.ref(item1)} |> Ref.make_ref(table)

    table
      |> Ref.put(item1)
      |> Ref.put(item2)
      |> Ref.put(item3)

    assert item1 == Ref.get(table, Ref.ref(item1))
    assert item2 == Ref.get(table, Ref.ref(item2))
    assert item3 == Ref.get(table, Ref.ref(item3))

    assert 3 == length(Table.cells(table))
    assert MapSet.new([Table.internal_ref(item1)]) == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new([Table.internal_ref(item1)]) == Table.outlinks(table, Table.internal_ref(item3))
    assert MapSet.new([Table.internal_ref(item2), Table.internal_ref(item3)]) == Table.inlinks(table, Table.internal_ref(item1))

    table |> Ref.delete(Ref.ref(item3))

    assert 2 == length(Table.cells(table))
    assert MapSet.new([Table.internal_ref(item1)]) == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new([Table.internal_ref(item2)]) == Table.inlinks(table, Table.internal_ref(item1))

    table |> Ref.delete(Ref.ref(item2))

    assert 0 == length(Table.cells(table))
    assert MapSet.new() == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new() == Table.inlinks(table, Table.internal_ref(item1))
  end

  test "link tracking, longer chain", %{table: table} do
    item1 = %Data{} |> Ref.make_ref(table)
    item2 = %Data{data: Ref.ref(item1)} |> Ref.make_ref(table)
    item3 = %Data{data: Ref.ref(item2)} |> Ref.make_ref(table)

    table
      |> Ref.put(item1)
      |> Ref.put(item2)
      |> Ref.put(item3)

    assert item1 == Ref.get(table, Ref.ref(item1))
    assert item2 == Ref.get(table, Ref.ref(item2))
    assert item3 == Ref.get(table, Ref.ref(item3))

    assert 3 == length(Table.cells(table))
    assert MapSet.new([Table.internal_ref(item1)]) == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new([Table.internal_ref(item2)]) == Table.outlinks(table, Table.internal_ref(item3))
    assert MapSet.new([Table.internal_ref(item2)]) == Table.inlinks(table, Table.internal_ref(item1))
    assert MapSet.new([Table.internal_ref(item3)]) == Table.inlinks(table, Table.internal_ref(item2))

    table |> Ref.delete(Ref.ref(item3))

    assert 0 == length(Table.cells(table))
    assert MapSet.new() == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new() == Table.inlinks(table, Table.internal_ref(item1))
  end

  test "link tracking, root", %{table: table} do
    item1 = %Data{} |> Ref.make_ref(table)
    item2 = %Data{data: Ref.ref(item1)} |> Ref.make_ref(table)
    item3 = %Data{data: Ref.ref(item2)} |> Ref.make_ref(table)

    table
      |> Ref.put(item1)
      |> Ref.put(item2)
      |> Ref.put(item3)
      |> Ref.root(item1)

    table |> Ref.delete(Ref.ref(item3))

    assert [item1] == Table.cells(table)
    assert MapSet.new() == Table.outlinks(table, Table.internal_ref(item2))
    assert MapSet.new() == Table.inlinks(table, Table.internal_ref(item1))
  end

  test "enforce checked in references", %{table: table} do
    item1 = %Data{} |> Ref.make_ref(table)
    item2 = %Data{data: Ref.ref(item1)} |> Ref.make_ref(table)

    assert_raise RuntimeError, fn ->
      Ref.put(table, item2)
    end
  end

  test "guard", %{table: table} do
    require Ulfnet.Ref
    ref = Ref.make_ref(table)
    assert Ref.is_cell_ref(ref)

    item = Ref.make_ref(%Data{}, table)
    assert Ref.is_cell(item)
  end

  def dump(table) do
    :ets.foldl(&IO.inspect/1, nil, table)
  end
end
