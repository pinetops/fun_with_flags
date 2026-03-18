defmodule FunWithFlags.Sandbox.Store do
  @moduledoc false
  # ETS-backed flag store for sandbox isolation.
  # Each sandbox table is a standalone flag store — no interaction with
  # the real persistence adapter, cache, or change notifications.

  alias FunWithFlags.{Flag, Gate}

  @doc "Look up a flag by name. Returns `{:ok, %Flag{}}` (empty flag if not found)."
  def lookup(table, flag_name) do
    case :ets.lookup(table, flag_name) do
      [{^flag_name, gates}] -> {:ok, Flag.new(flag_name, gates)}
      [] -> {:ok, Flag.new(flag_name)}
    end
  end

  @doc "Add or merge a gate into a flag."
  def put(table, flag_name, %Gate{} = gate) do
    existing_gates =
      case :ets.lookup(table, flag_name) do
        [{^flag_name, gates}] -> gates
        [] -> []
      end

    new_gates = merge_gate(existing_gates, gate)
    :ets.insert(table, {flag_name, new_gates})
    {:ok, Flag.new(flag_name, new_gates)}
  end

  @doc "Delete an entire flag."
  def delete(table, flag_name) do
    :ets.delete(table, flag_name)
    {:ok, Flag.new(flag_name)}
  end

  @doc "Delete a specific gate from a flag."
  def delete(table, flag_name, %Gate{} = gate) do
    case :ets.lookup(table, flag_name) do
      [{^flag_name, gates}] ->
        new_gates = remove_gate(gates, gate)
        :ets.insert(table, {flag_name, new_gates})
        {:ok, Flag.new(flag_name, new_gates)}

      [] ->
        {:ok, Flag.new(flag_name)}
    end
  end

  @doc "Return all flags in the table."
  def all_flags(table) do
    flags =
      :ets.tab2list(table)
      |> Enum.map(fn {name, gates} -> Flag.new(name, gates) end)

    {:ok, flags}
  end

  @doc "Return all flag names in the table."
  def all_flag_names(table) do
    names =
      :ets.tab2list(table)
      |> Enum.map(fn {name, _gates} -> name end)

    {:ok, names}
  end

  # Merge a gate into an existing list, replacing any gate of the same type+for.
  # Percentage gates replace by type only (there can be only one of each).
  defp merge_gate(gates, new_gate) do
    replaced =
      Enum.map(gates, fn existing ->
        if same_gate_id?(existing, new_gate), do: new_gate, else: existing
      end)

    if Enum.any?(gates, &same_gate_id?(&1, new_gate)) do
      replaced
    else
      [new_gate | gates]
    end
  end

  # Remove a gate matching by type+for.
  defp remove_gate(gates, target) do
    Enum.reject(gates, &same_gate_id?(&1, target))
  end

  # Two gates have the same identity if they share type and target.
  # For percentage gates, there's only one per type regardless of the ratio.
  defp same_gate_id?(%Gate{type: type, for: for1}, %Gate{type: type, for: for2}) do
    case type do
      :percentage_of_time -> true
      :percentage_of_actors -> true
      _ -> for1 == for2
    end
  end

  defp same_gate_id?(_, _), do: false
end
