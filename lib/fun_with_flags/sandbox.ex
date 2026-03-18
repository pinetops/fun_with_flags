defmodule FunWithFlags.Sandbox do
  @moduledoc """
  A pool of ETS tables for test isolation of feature flags.

  ## Usage

  Start the pool in your `test/test_helper.exs`:

      FunWithFlags.Sandbox.start()

  Then use `FunWithFlags.Sandbox.Case` in your test modules, or
  manually call `checkout/1` and `checkin/1`:

      setup do
        table = FunWithFlags.Sandbox.checkout()
        on_exit(fn -> FunWithFlags.Sandbox.checkin(table) end)
        :ok
      end

  When a sandbox is checked out, all `FunWithFlags` calls in the
  current process use an isolated ETS table instead of the real store.

  ## Options

  * `:pool_size` — number of ETS tables to pre-create (default: `System.schedulers_online()`)
  * `:flags` — keyword list of flags to pre-seed on checkout, e.g. `[my_flag: true, other: false]`
  """

  use GenServer

  alias FunWithFlags.{Gate, Sandbox.Store}

  @type table :: :ets.table()

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc """
  Start the sandbox pool.

  Options:
  * `:pool_size` — defaults to `System.schedulers_online()`
  """
  def start(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check out a clean ETS table for the current process.

  Options:
  * `:flags` — keyword list of `[flag_name: boolean]` to pre-seed
  * `:timeout` — GenServer call timeout (default: 5_000)
  """
  def checkout(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    table = GenServer.call(__MODULE__, :checkout, timeout)
    Process.put(:fwf_sandbox, table)
    seed_flags(table, Keyword.get(opts, :flags, []))
    table
  end

  @doc """
  Return a checked-out table to the pool and clear the process dictionary.
  """
  def checkin(table) do
    Process.delete(:fwf_sandbox)
    GenServer.call(__MODULE__, {:checkin, table})
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, System.schedulers_online())

    tables =
      for i <- 1..pool_size do
        :ets.new(:"fwf_sandbox_#{i}", [:set, :public, read_concurrency: true])
      end

    {:ok, %{available: tables, waiting: :queue.new()}}
  end

  @impl true
  def handle_call(:checkout, from, %{available: [], waiting: waiting} = state) do
    {:noreply, %{state | waiting: :queue.in(from, waiting)}}
  end

  def handle_call(:checkout, _from, %{available: [table | rest]} = state) do
    clear_table(table)
    {:reply, table, %{state | available: rest}}
  end

  def handle_call({:checkin, table}, _from, %{available: available, waiting: waiting} = state) do
    case :queue.out(waiting) do
      {{:value, next}, new_waiting} ->
        clear_table(table)
        GenServer.reply(next, table)
        {:reply, :ok, %{state | waiting: new_waiting}}

      {:empty, _} ->
        {:reply, :ok, %{state | available: [table | available]}}
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp clear_table(table) do
    :ets.delete_all_objects(table)
  end

  defp seed_flags(table, flags) do
    for {flag_name, enabled} <- flags do
      gate = Gate.new(:boolean, enabled)
      Store.put(table, flag_name, gate)
    end
  end
end
