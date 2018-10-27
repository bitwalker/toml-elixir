defmodule Toml.Test do
  use ExUnit.Case

  import Toml.Test.Assertions

  describe "decoding from various sources" do
    test "decode" do
      input = File.read!(Path.join([__DIR__, "fixtures", "0.5.0.toml"]))
      assert {:ok, _} = Toml.decode(input)
      assert %{"integer" => 2} = Toml.decode!(input)
    end

    test "decode_stream" do
      input = File.stream!(Path.join([__DIR__, "fixtures", "0.5.0.toml"]))
      assert {:ok, _} = Toml.decode_stream(input)
      assert %{"integer" => 2} = Toml.decode_stream!(input)
    end

    test "decode_file" do
      input = Path.join([__DIR__, "fixtures", "0.5.0.toml"])
      assert {:ok, _} = Toml.decode_file(input)
      assert %{"integer" => 2} = Toml.decode_file!(input)
    end
  end

  describe "errors" do
    test "invalid filename" do
      assert {:error, "invalid :filename" <> _} = Toml.decode("[a]\na = 1", filename: :foo)
      file = Path.join([__DIR__, "fixtures", "0.5.0.toml"])
      assert {:error, "invalid :filename" <> _} = Toml.decode_file(file, filename: :foo)
      stream = ["[a]", "b = 2"] |> Stream.concat(["[b]", "a = 1"])
      assert {:error, "invalid :filename" <> _} = Toml.decode_stream(stream, filename: :foo)

      assert_raise ArgumentError, "invalid :filename option ':foo', must be a binary!", fn ->
        Toml.decode!("[a]\na = 1", filename: :foo)
      end

      assert_raise ArgumentError, "invalid :filename option ':foo', must be a binary!", fn ->
        Toml.decode_file!(file, filename: :foo)
      end

      assert_raise ArgumentError, "invalid :filename option ':foo', must be a binary!", fn ->
        Toml.decode_stream!(stream, filename: :foo)
      end
    end

    test "invalid path" do
      assert {:error, "unable to open file 'noexist.toml'" <> _} =
               Toml.decode_file("noexist.toml")

      assert_raise File.Error, fn ->
        Toml.decode_file!("noexist.toml")
      end
    end

    test "formatting with crlf matches fomatting with lf" do
      input_crlf = "[a]" <> <<?\r, ?\n>> <> "b = 1" <> <<?\r, ?\n>> <> "[b] c = 1"
      input_lf = "[a]" <> <<?\n>> <> "b = 1" <> <<?\n>> <> "[b] c = 1"
      assert {:error, {:invalid_toml, reason}} = Toml.decode(input_crlf)
      assert {:error, {:invalid_toml, ^reason}} = Toml.decode(input_lf)
    end
  end

  describe "date/time types" do
    test "date" do
      assert {:ok, %{"n" => ~D[2018-06-30]}} = decode("n = 2018-06-30")
      assert {:ok, %{"n" => ~D[2018-06-30]}} = decode("n = 2018-06-30 ")
      assert {:error, {:invalid_toml, _}} = decode("n = 2018-16-30")
      assert {:error, {:invalid_toml, _}} = decode("n = 2018-16-0")
    end

    test "time" do
      assert {:ok, %{"n" => ~T[12:30:58]}} = decode("n = 12:30:58")
      assert {:ok, %{"n" => ~T[12:30:58.030]}} = decode("n = 12:30:58.030")
      assert {:error, {:invalid_toml, _}} = decode("n = 12:30:58.A")
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

  describe "numbers" do
    test "float1" do
      assert %{"f" => 1.0e7} = Toml.decode!("f = 1000e4")
      assert %{"f" => 1.0e8} = Toml.decode!("f = 1000_0e4")
      assert {:error, {:invalid_toml, _}} = Toml.decode("f = +_")
      assert {:error, {:invalid_toml, _}} = Toml.decode("f = +1.0.3")
      assert {:error, {:invalid_toml, _}} = Toml.decode("f = +1.0_A")
    end
  end

  test "example.toml" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])
    assert_toml_valid(input)
  end

  test "example.toml (keys: :atoms)" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])

    assert {:ok, %{table: %{subtable: %{key: "another value"}}}} =
             Toml.decode_file(input, keys: :atoms)
  end

  test "example.toml (keys: :atoms!)" do
    input = Path.join([__DIR__, "fixtures", "example.toml"])

    # Expected to fail
    assert {:error, {:invalid_toml, "unable to convert " <> _}} =
             Toml.decode_file(input, keys: :atoms!)
  end

  test "0.5.0.toml" do
    input = Path.join([__DIR__, "fixtures", "0.5.0.toml"])
    assert_toml_valid(input)
  end

  test "issue #9" do
    input = """
    # config.toml

    [myapp."MyApp.Endpoint".url]
    scheme = "https"
    host = "my-app.com"
    port = 443

    # Table defined after a subtable
    [myapp."MyApp.Endpoint"]
    secret_key_base = "secret"
    """

    assert {:ok,
            %{
              "myapp" => %{
                "MyApp.Endpoint" => %{
                  "secret_key_base" => "secret",
                  "url" => %{"scheme" => "https", "host" => "my-app.com", "port" => 443}
                }
              }
            }} = Toml.decode(input)
  end

  defp decode(str) when is_binary(str) do
    Toml.decode(str)
  end
end
