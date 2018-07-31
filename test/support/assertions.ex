defmodule Toml.Test.Assertions do
  @moduledoc false
  import ExUnit.Assertions

  alias Toml.Test.JsonConverter

  @doc """
  Given a path to a TOML file, asserts that parsing succeeds and
  conversion to it's JSON equivalent matches the expected result.

  The expected result should be contained in a .json file of the same
  name as the .toml file given, in the same directory. The result is
  compared with `assert_deep_equal/2`.
  """
  def assert_toml_valid(path) do
    json = Path.join([Path.dirname(path), Path.basename(path, ".toml") <> ".json"])

    case Toml.decode_file(path) do
      {:error, {:invalid_toml, reason}} when is_binary(reason) ->
        flunk(reason)

      {:ok, decoded} ->
        expected = JsonConverter.parse_json_file!(json)
        typed = JsonConverter.to_typed_map(decoded)
        assert_deep_equal(expected, typed)
    end
  end

  @doc """
  Asserts that two items are deeply equivalent, meaning that
  all lists have the same items, all maps have the same keys, and all values
  are the same. Order of items is not considered in this equality comparison.
  """
  def assert_deep_equal(a, b) do
    if do_deep_equal(a, b) do
      assert true
    else
      assert a == b
    end
  end

  defp do_deep_equal(a, b) when is_map(a) and is_map(b) do
    asort = a |> Map.to_list() |> Enum.sort_by(&to_sort_key/1)
    bsort = b |> Map.to_list() |> Enum.sort_by(&to_sort_key/1)

    if map_size(a) == map_size(b) do
      for {{ak, av}, {bk, bv}} <- Enum.zip(asort, bsort) do
        if ak != bk do
          false
        else
          do_deep_equal(av, bv)
        end
      end
    else
      false
    end
  end

  defp do_deep_equal(a, a), do: true

  defp do_deep_equal(a, b) when is_list(a) and is_list(b) do
    if length(a) == length(b) do
      asort = Enum.sort_by(a, &to_sort_key/1)
      bsort = Enum.sort_by(b, &to_sort_key/1)

      for {ai, bi} <- Enum.zip(asort, bsort) do
        do_deep_equal(ai, bi)
      end
    else
      a == b
    end
  end

  defp do_deep_equal(a, b) do
    a == b
  end

  defp to_sort_key(v) when is_map(v), do: Enum.sort(Map.keys(v))
  defp to_sort_key(v) when is_list(v), do: Enum.sort_by(v, &to_sort_key/1)
  defp to_sort_key(v), do: v
end
