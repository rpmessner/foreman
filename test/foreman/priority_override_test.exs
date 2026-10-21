defmodule Foreman.PriorityOverrideTest do
  use ExUnit.Case, async: true
  alias Foreman.PriorityOverride, as: Machine

  test "board values own priority until the file catches up" do
    assert Machine.step(:file, {:set, %{priority: 0, file: 2}}, nil) ==
             {:board, [store: :override]}

    assert Machine.step(:board, {:set, %{priority: 1, file: 2}}, nil) ==
             {:board, [store: :override]}

    assert Machine.step(:board, {:synced, %{priority: 1, file: 2}}, nil) == {:board, []}

    assert Machine.step(:board, {:synced, %{priority: 1, file: 1}}, nil) ==
             {:file, [clear: :override]}

    assert Machine.step(:board, {:set, %{priority: 2, file: 2}}, nil) ==
             {:file, [clear: :override]}

    assert Machine.step(:file, {:set, %{priority: 2, file: 2}}, nil) == {:file, []}
    assert Machine.step(:file, :synced, nil) == {:file, []}
  end
end
