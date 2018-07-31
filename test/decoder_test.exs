defmodule Toml.Test.DecoderTests do
  @moduledoc """
  Like `Toml.Test.TomlTestTests`, but runs against a set of collected valid and invalid tests
  which aren't part of `toml-test`
  """
  use ExUnit.Case

  import Toml.Test.Assertions

  @test_dir Path.join([__DIR__, "fixtures"])
  @valid_tests Path.wildcard(Path.join([@test_dir, "valid", "*.toml"]))
  @num_valid length(@valid_tests)
  @invalid_tests Path.wildcard(Path.join([@test_dir, "invalid", "*.toml"]))

  # For each test, we want to generate useful line information for `mix test path/to/test:line` filters
  # So we map an index to each test
  for {valid_test, line} <- Enum.with_index(@valid_tests),
      name = Path.basename(valid_test, ".toml") do
    # Then offset it using the current line in the environment
    line = __ENV__.line + line
    # Build the test definition
    quoted =
      quote line: line do
        @toml_test unquote(name)
        @toml_test_path unquote(valid_test)
        @toml_test_type :valid
        @tag toml_test: @toml_test
        @tag toml_test_type: :valid
        test "#{@toml_test} is valid" do
          assert_toml_valid(@toml_test_path)
        rescue
          err in [ExUnit.AssertionError] ->
            # Dump the TOML for better test failure context
            msg =
              err.message <>
                "\nExpected the following TOML to be considered valid:\n\n---\n#{
                  File.read!(@toml_test_path)
                }\n---"

            reraise %ExUnit.AssertionError{err | message: msg}, System.stacktrace()
        end
      end

    # And eval it in the module environment, resulting in a test as if it was defined by hand
    # rather than in the body of a loop
    Module.eval_quoted(%Macro.Env{__ENV__ | line: line}, quoted)
  end

  # The only difference for the invalid tests is that we additionally offset it by the number of valid tests
  for {invalid_test, line} <- Enum.with_index(@invalid_tests),
      name = Path.basename(invalid_test, ".toml") do
    line = __ENV__.line + line + @num_valid

    quoted =
      quote line: @num_valid + __ENV__.line + line do
        @toml_test unquote(name)
        @toml_test_path unquote(invalid_test)
        @tag toml_test: @toml_test
        @tag toml_test_type: :invalid
        test "#{@toml_test} is invalid" do
          assert {:error, {:invalid_toml, _}} = Toml.decode_file(@toml_test_path)
        rescue
          err in [ExUnit.AssertionError] ->
            msg =
              err.message <>
                "\n\nExpected the following TOML to be considered invalid:\n\n---\n#{
                  File.read!(@toml_test_path)
                }\n---"

            reraise %ExUnit.AssertionError{err | message: msg}, System.stacktrace()
        end
      end

    Module.eval_quoted(%Macro.Env{__ENV__ | line: line}, quoted)
  end
end
