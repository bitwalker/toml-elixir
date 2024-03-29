defmodule Toml.Test.JsonConverter do
  @moduledoc false

  def parse_toml_file!(path) do
    case Toml.decode_file(path) do
      {:ok, map} ->
        Jason.encode!(to_typed_map(map), pretty: true)

      {:error, _} = err ->
        err
    end
  end

  def parse_json_file!(path) do
    Jason.decode!(File.read!(path))
  end

  def to_typed_map(map) when is_map(map) do
    for {k, v} <- map, v2 = to_typed_value(v), into: %{} do
      {k, v2}
    end
  end

  def to_json_map(map) when is_map(map) do
    for {k, v} <- map, into: %{} do
      {k, to_json_value(v)}
    end
  end

  defp to_typed_value(:infinity),
    do: %{"type" => "integer", "value" => "Infinity"}

  defp to_typed_value(:negative_infinity),
    do: %{"type" => "integer", "value" => "-Infinity"}

  defp to_typed_value(:nan),
    do: %{"type" => "integer", "value" => "NaN"}

  defp to_typed_value(:negative_nan),
    do: %{"type" => "integer", "value" => "-NaN"}

  defp to_typed_value(n) when is_integer(n),
    do: %{"type" => "integer", "value" => Integer.to_string(n)}

  defp to_typed_value(n) when is_float(n),
    do: %{"type" => "float", "value" => Float.to_string(n)}

  defp to_typed_value(s) when is_binary(s),
    do: %{"type" => "string", "value" => s}

  defp to_typed_value(true),
    do: %{"type" => "bool", "value" => "true"}

  defp to_typed_value(false),
    do: %{"type" => "bool", "value" => "false"}

  # Empty lists are treated plainly
  defp to_typed_value([]), do: []

  # Array of structs (values)
  defp to_typed_value([%_{} | _] = list) do
    %{"type" => "array", "value" => Enum.map(list, &to_typed_value/1)}
  end

  # Array value
  defp to_typed_value(list) when is_list(list),
    do: %{"type" => "array", "value" => Enum.map(list, &to_typed_value/1)}

  defp to_typed_value(%Date{} = d),
    do: %{"type" => "datetime", "value" => Date.to_iso8601(d)}

  defp to_typed_value(%Time{} = d),
    do: %{"type" => "datetime", "value" => Time.to_iso8601(d)}

  defp to_typed_value(%DateTime{} = d),
    do: %{"type" => "datetime", "value" => DateTime.to_iso8601(d)}

  defp to_typed_value(%NaiveDateTime{} = d),
    do: %{"type" => "datetime", "value" => NaiveDateTime.to_iso8601(d)}

  defp to_typed_value(map) when is_map(map) do
    to_typed_map(map)
  end

  defp to_json_value(:infinity),
    do: "Infinity"

  defp to_json_value(:negative_infinity),
    do: "-Infinity"

  defp to_json_value(:nan),
    do: "NaN"

  defp to_json_value(:negative_nan),
    do: "-NaN"

  defp to_json_value(n) when is_integer(n),
    do: n

  defp to_json_value(n) when is_float(n),
    do: n

  defp to_json_value(s) when is_binary(s),
    do: s

  defp to_json_value(true),
    do: true

  defp to_json_value(false),
    do: false

  # Empty lists are treated plainly
  defp to_json_value([]), do: []

  # Array value
  defp to_json_value(list) when is_list(list),
    do: Enum.map(list, &to_json_value/1)

  defp to_json_value(%Date{} = d),
    do: Date.to_iso8601(d)

  defp to_json_value(%Time{} = d),
    do: Time.to_iso8601(d)

  defp to_json_value(%DateTime{} = d),
    do: DateTime.to_iso8601(d)

  defp to_json_value(%NaiveDateTime{} = d),
    do: NaiveDateTime.to_iso8601(d)

  defp to_json_value(map) when is_map(map) do
    to_json_map(map)
  end
end
