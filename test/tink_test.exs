defmodule TinkTest do
  use ExUnit.Case
  doctest Tink

  test "greets the world" do
    assert Tink.hello() == :world
  end
end
