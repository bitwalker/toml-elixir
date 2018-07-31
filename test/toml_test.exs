defmodule Toml.Test do
  use ExUnit.Case
  
  import Toml.Test.Assertions

  describe "date/time types" do
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
  end
  
  test "example.toml" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])
    assert_toml_valid(input)
  end
  
  test "example.toml (keys: :atoms)" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])
    assert {:ok, %{table: %{subtable: %{key: "another value"}}}} = Toml.decode_file(input, keys: :atoms)
  end
  
  test "0.5.0.toml" do
    input = Path.join([__DIR__, "fixtures", "0.5.0.toml"])
    assert_toml_valid(input)
  end

  defp decode(str) when is_binary(str) do
    Toml.decode(str)
  end
end
