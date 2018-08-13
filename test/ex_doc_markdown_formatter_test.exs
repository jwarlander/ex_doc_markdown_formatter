defmodule ExDocMarkdownFormatterTest do
  use ExUnit.Case
  doctest ExDocMarkdownFormatter

  test "greets the world" do
    assert ExDocMarkdownFormatter.hello() == :world
  end
end
