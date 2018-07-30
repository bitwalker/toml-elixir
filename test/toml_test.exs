defmodule Toml.Test do
  use ExUnit.Case
  
  import Toml.Test.Assertions

  describe "basic syntax" do
    test "integers" do
      assert {:ok, %{"n" => 1}} = decode("n = 1")
      assert {:ok, %{"n" => 1}} = decode("n = +1")
      assert {:ok, %{"n" => -1}} = decode("n = -1")
      assert {:ok, %{"n" => 105}} = decode("n = 105")
      assert {:ok, %{"n" => 3500}} = decode("n = 3_500")
      assert {:ok, %{"n" => -3500}} = decode("n = -3_500")
    end
    
    test "floats" do
      assert {:ok, %{"n" => 1.0}} = decode("n = 1.0")
      assert {:ok, %{"n" => 1.0}} = decode("n = +1.0")
      assert {:ok, %{"n" => -1.0}} = decode("n = -1.0")
      assert {:ok, %{"n" => 1.0e2}} = decode("n = 1.0e2")
      assert {:ok, %{"n" => 1.0e2}} = decode("n = 1e2")
      assert {:ok, %{"n" => 1.0e2}} = decode("n = 1.0E2")
      assert {:ok, %{"n" => 1.0e2}} = decode("n = 1E2")
    end
    
    test "hexadecimal" do
      assert {:ok, %{"n" => 0xAE}} = decode("n = 0xAE")
      assert {:ok, %{"n" => 0xAE}} = decode("n = 0xae")
    end
    
    test "octal" do
      assert {:ok, %{"n" => 0o777}} = decode("n = 0o777")
    end
    
    test "binary numbers" do
      assert {:ok, %{"n" => 0b10101}} = decode("n = 0b10101")
    end
    
    test "basic string" do
      assert {:ok, %{"n" => "hello world!"}} = decode("n = \"hello world!\"")
    end
    
    test "literal string" do
      assert {:ok, %{"n" => "\"hello world!\""}} = decode("n = '\"hello world!\"'")
    end

    test "quoted string" do
      assert {:ok, %{"n" => "hello world!"}} = decode("n = \"hello world!\"")
      assert {:ok, %{"n" => "\"hello world!\""}} = decode("n = \"\\\"hello world!\\\"\"")
    end
    
    test "date" do
      assert {:ok, %{"n" => ~D[2018-06-30]}} = decode("n = 2018-06-30")
      assert {:error, {:invalid_toml, _}} = decode("n = 2018-16-30")
      assert {:error, {:invalid_toml, _}} = decode("n = 2018-16-0")
    end
    
    test "time" do
      assert {:ok, %{"n" => ~T[12:30:58]}} = decode("n = 12:30:58")
      assert {:ok, %{"n" => ~T[12:30:58.030]}} = decode("n = 12:30:58.030")
    end
    
    test "date/time (local)" do
      assert {:ok, %{"n" => ~N[2018-06-30T12:30:58]}} = decode("n = 2018-06-30T12:30:58")
      assert {:ok, %{"n" => ~N[2018-06-30T12:30:58]}} = decode("n = 2018-06-30 12:30:58")
      assert {:ok, %{"n" => ~N[2018-06-30T12:30:58.030]}} = decode("n = 2018-06-30 12:30:58.030")
    end
    
    test "date/time (utc)" do
      expected = DateTime.from_naive!(~N[2018-06-30T12:30:58], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = decode("n = 2018-06-30T12:30:58Z")
      expected = DateTime.from_naive!(~N[2018-06-30T12:30:58.030], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = decode("n = 2018-06-30 12:30:58.030Z")
    end

    test "date/time (utc offset)" do
      expected = DateTime.from_naive!(~N[2018-06-30T19:30:58.030], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = decode("n = 2018-06-30 12:30:58.030+07:00")
      expected = DateTime.from_naive!(~N[2018-06-30T05:30:58.030], "Etc/UTC")
      assert {:ok, %{"n" => ^expected}} = decode("n = 2018-06-30 12:30:58.030-07:00")
    end
    
    test "bare keys" do
      assert {:ok, %{"n" => 1}} = decode("n = 1")
      assert {:ok, %{"n1" => 1}} = decode("n1 = 1")
      assert {:ok, %{"n_1" => 1}} = decode("n_1 = 1")
      assert {:ok, %{"n-1" => 1}} = decode("n-1 = 1")
      assert {:error, {:invalid_toml, _}} = decode("n! = 1")
    end
    
    test "quoted keys" do
      assert {:ok, %{"key with space" => 1}} = decode("\"key with space\" = 1")
      assert {:ok, %{"key with $p@c3" => 1}} = decode("\"key with $p@c3\" = 1")
      assert {:ok, %{"literal key" => 1}} = decode("'literal key' = 1")
    end
    
    test "dotted keys" do
      assert {:ok, %{"a" => %{"b" => 1}}} = decode("a.b = 1")
      assert {:ok, %{"a" => %{"b" => %{"c" => 1}}}} = decode("a.b.c = 1")
      assert {:ok, %{"a" => %{"mixed keys" => 1}}} = decode("a.\"mixed keys\" = 1")
    end
    
    test "tables" do
      expected = %{}
      assert {:ok, %{"a" => ^expected}} = decode("[a]\n")
      assert {:ok, %{"a" => %{"b" => ^expected}}} = decode("[a.b]\n")
      assert {:ok, %{"a" => %{"foo" => ^expected}}} = decode("[a.\"foo\"]\n")
      expected = %{"n" => 1}
      assert {:ok, %{"a" => ^expected}} = decode("[a]\nn = 1")
      assert {:ok, %{"a" => %{"b" => ^expected}}} = decode("[a.b]\nn = 1")
      assert {:ok, %{"a" => %{"foo" => ^expected}}} = decode("[a.\"foo\"]\nn = 1")
      assert {:ok, %{"a" => %{"n" => 1, "b" => %{"n" => 2}}}} = decode("[a]\nn = 1\n[a.b]\nn = 2")
      assert {:ok, %{"a" => %{"n" => 2, "b" => %{"n" => 1}}}} = decode("[a.b]\nn = 1\n[a]\nn = 2")
    end
  end
  
  test "example.toml" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])
    assert_toml_valid(input)
  end
  
  test "example.toml (keys: :atoms)" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])
    assert {:ok, %{table: %{subtable: %{key: "another value"}}}} = Toml.decode_file(input, keys: :atoms)
  end
  
  test "test.toml" do
    input = Path.join([__DIR__, "fixtures", "test.toml"])
    assert_toml_valid(input)
  end
  
  test "hard.toml" do
    input = Path.join([__DIR__, "fixtures", "hard.toml"])
    assert_toml_valid(input)
  end
  
  test "hard-unicode.toml" do
    input = Path.join([__DIR__, "fixtures", "hard-unicode.toml"])
    assert_toml_valid(input)
  end
  
  test "hard.toml (invalid variants)" do
    for input <- Path.wildcard(Path.join([__DIR__, "fixtures", "hard-invalid*.toml"])) do
      assert {:error, {:invalid_toml, _}} = decode_file(input)
    end
  end
  
  defp decode(str) when is_binary(str) do
    Toml.decode(str)
  end
  
  defp decode_file(path) when is_binary(path) do
    Toml.decode_file(path)
  end
end
