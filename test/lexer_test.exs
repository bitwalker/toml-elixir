defmodule Toml.Test.LexerTest do
  use ExUnit.Case

  alias Toml.Lexer

  setup do
    {:ok, lexer} = Lexer.new("n = 3_500")

    on_exit(fn ->
      Lexer.stop(lexer)
    end)

    %{lexer: lexer}
  end

  test "lexes expected tokens", %{lexer: lexer} do
    assert {:ok, {:alpha, _, "n", _}} = Lexer.pop(lexer)
    assert {:ok, {:whitespace, _, _, _}} = Lexer.pop(lexer)
    assert {:ok, {?=, _, _, _}} = Lexer.pop(lexer)
    assert {:ok, {:whitespace, _, _, _}} = Lexer.pop(lexer)
    assert {:ok, {:digits, _, "3", _}} = Lexer.pop(lexer)
    assert {:ok, {?_, _, _, _}} = Lexer.pop(lexer)
    assert {:ok, {:digits, _, "500", _}} = Lexer.pop(lexer)
    assert {:ok, {:eof, _, _, _}} = Lexer.pop(lexer)
    assert {:ok, {:eof, _, _, _}} = Lexer.pop(lexer)
  end

  test "can peek", %{lexer: lexer} do
    assert {:ok, {:alpha, _, "n", _}} = Lexer.peek(lexer)
    assert {:ok, {:alpha, _, "n", _}} = Lexer.peek(lexer)
    assert {:ok, {:alpha, _, "n", _}} = Lexer.peek(lexer)
    assert {:ok, {:alpha, _, "n", _}} = Lexer.peek(lexer)
  end

  test "can advance", %{lexer: lexer} do
    assert {:ok, {:alpha, _, "n", _}} = Lexer.peek(lexer)
    assert :ok = Lexer.advance(lexer)
    assert {:ok, {:whitespace, _, _, _}} = Lexer.peek(lexer)
    assert {:ok, {:whitespace, _, _, _}} = Lexer.peek(lexer)
  end

  test "can pop", %{lexer: lexer} do
    assert {:ok, {:alpha, _, "n", _}} = Lexer.peek(lexer)
    assert {:ok, {:alpha, _, "n", _}} = Lexer.pop(lexer)
    assert {:ok, {:whitespace, _, _, _}} = Lexer.pop(lexer)
  end

  test "can push", %{lexer: lexer} do
    assert :ok = Lexer.push(lexer, {:alpha, -1, "foo", -1})
    assert {:ok, {:alpha, -1, "foo", -1}} = Lexer.pop(lexer)
  end
end
