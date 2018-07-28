defmodule Toml.Test do
  use ExUnit.Case
  
  import Toml.Test.Assertions

  describe "basic syntax" do
    test "integers" do
      assert {:ok, %{"n" => 1}} = parse("n = 1")
      assert {:ok, %{"n" => 1}} = parse("n = +1")
      assert {:ok, %{"n" => -1}} = parse("n = -1")
      assert {:ok, %{"n" => 105}} = parse("n = 105")
      assert {:ok, %{"n" => 3500}} = parse("n = 3_500")
      assert {:ok, %{"n" => -3500}} = parse("n = -3_500")
    end
    
    test "floats" do
      assert {:ok, %{"n" => 1.0}} = parse("n = 1.0")
      assert {:ok, %{"n" => 1.0}} = parse("n = +1.0")
      assert {:ok, %{"n" => -1.0}} = parse("n = -1.0")
      assert {:ok, %{"n" => 1.0e2}} = parse("n = 1.0e2")
      assert {:ok, %{"n" => 1.0e2}} = parse("n = 1e2")
      assert {:ok, %{"n" => 1.0e2}} = parse("n = 1.0E2")
      assert {:ok, %{"n" => 1.0e2}} = parse("n = 1E2")
    end
    
    test "hexadecimal" do
      assert {:ok, %{"n" => 0xAE}} = parse("n = 0xAE")
      assert {:ok, %{"n" => 0xAE}} = parse("n = 0xae")
    end
    
    test "octal" do
      assert {:ok, %{"n" => 0o777}} = parse("n = 0o777")
    end
    
    test "binary numbers" do
      assert {:ok, %{"n" => 0b10101}} = parse("n = 0b10101")
    end
    
    test "basic string" do
      assert {:ok, %{"n" => "hello world!"}} = parse("n = \"hello world!\"")
    end
    
    test "literal string" do
      assert {:ok, %{"n" => "\"hello world!\""}} = parse("n = '\"hello world!\"'")
    end

    test "quoted string" do
      assert {:ok, %{"n" => "hello world!"}} = parse("n = \"hello world!\"")
      assert {:ok, %{"n" => "\"hello world!\""}} = parse("n = \"\\\"hello world!\\\"\"")
    end
    
    test "date" do
      assert {:ok, %{"n" => ~D[2018-06-30]}} = parse("n = 2018-06-30")
      assert {:error, {:invalid_toml, _}} = parse("n = 2018-16-30")
      assert {:error, {:invalid_toml, _}} = parse("n = 2018-16-0")
    end
    
    test "time" do
      assert {:ok, %{"n" => ~T[12:30:58]}} = parse("n = 12:30:58")
      assert {:ok, %{"n" => ~T[12:30:58.030]}} = parse("n = 12:30:58.030")
    end
    
    test "date/time (local)" do
      assert {:ok, %{"n" => ~N[2018-06-30T12:30:58]}} = parse("n = 2018-06-30T12:30:58")
      assert {:ok, %{"n" => ~N[2018-06-30T12:30:58]}} = parse("n = 2018-06-30 12:30:58")
      assert {:ok, %{"n" => ~N[2018-06-30T12:30:58.030]}} = parse("n = 2018-06-30 12:30:58.030")
    end
    
    test "date/time (utc)" do
      expected = DateTime.from_naive!(~N[2018-06-30T12:30:58], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = parse("n = 2018-06-30T12:30:58Z")
      expected = DateTime.from_naive!(~N[2018-06-30T12:30:58.030], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = parse("n = 2018-06-30 12:30:58.030Z")
    end

    test "date/time (utc offset)" do
      expected = DateTime.from_naive!(~N[2018-06-30T19:30:58.030], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = parse("n = 2018-06-30 12:30:58.030+07:00")
      expected = DateTime.from_naive!(~N[2018-06-30T05:30:58.030], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = parse("n = 2018-06-30 12:30:58.030-07:00")
    end
    
    test "bare keys" do
      assert {:ok, %{"n" => 1}} = parse("n = 1")
      assert {:ok, %{"n1" => 1}} = parse("n1 = 1")
      assert {:ok, %{"n_1" => 1}} = parse("n_1 = 1")
      assert {:ok, %{"n-1" => 1}} = parse("n-1 = 1")
      assert {:error, {:invalid_toml, _}} = parse("n! = 1")
    end
    
    test "quoted keys" do
      assert {:ok, %{"key with space" => 1}} = parse("\"key with space\" = 1")
      assert {:ok, %{"key with $p@c3" => 1}} = parse("\"key with $p@c3\" = 1")
      assert {:ok, %{"literal key" => 1}} = parse("'literal key' = 1")
    end
    
    test "dotted keys" do
      assert {:ok, %{"a" => %{"b" => 1}}} = parse("a.b = 1")
      assert {:ok, %{"a" => %{"b" => %{"c" => 1}}}} = parse("a.b.c = 1")
      assert {:ok, %{"a" => %{"mixed keys" => 1}}} = parse("a.\"mixed keys\" = 1")
    end
    
    test "tables" do
      expected = %{}
      assert {:ok, %{"a" => ^expected}} = parse("[a]\n")
      assert {:ok, %{"a" => %{"b" => ^expected}}} = parse("[a.b]\n")
      assert {:ok, %{"a" => %{"foo" => ^expected}}} = parse("[a.\"foo\"]\n")
      expected = %{"n" => 1}
      assert {:ok, %{"a" => ^expected}} = parse("[a]\nn = 1")
      assert {:ok, %{"a" => %{"b" => ^expected}}} = parse("[a.b]\nn = 1")
      assert {:ok, %{"a" => %{"foo" => ^expected}}} = parse("[a.\"foo\"]\nn = 1")
      assert {:ok, %{"a" => %{"n" => 1, "b" => %{"n" => 2}}}} = parse("[a]\nn = 1\n[a.b]\nn = 2")
      assert {:ok, %{"a" => %{"n" => 2, "b" => %{"n" => 1}}}} = parse("[a.b]\nn = 1\n[a]\nn = 2")
    end
  end
  
  test "example.toml" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])
    assert_toml_valid(input)
  end
  
  defp parse(str) when is_binary(str) do
    Toml.Parser.parse(str)
  end
end
