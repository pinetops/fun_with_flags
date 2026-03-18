defmodule FunWithFlags.Sandbox.Case do
  @moduledoc """
  ExUnit case template that automatically checks out and checks in
  a `FunWithFlags.Sandbox` table for each test.

      use FunWithFlags.Sandbox.Case
  """

  use ExUnit.CaseTemplate

  setup do
    if Process.whereis(FunWithFlags.Sandbox) do
      table = FunWithFlags.Sandbox.checkout()
      on_exit(fn -> FunWithFlags.Sandbox.checkin(table) end)
      %{fwf_table: table}
    else
      :ok
    end
  end
end
