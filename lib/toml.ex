defmodule Toml do
  @moduledoc File.read!(Path.join([__DIR__, "..", "README.md"]))
  
  @type opt :: {:keys, :atom | :string}
             | {:filename, String.t}
  @type opts :: [opt]

  @doc """
  Parse the given binary as TOML content
  
  ## Options

  You can pass the following options to configure the parsing behavior:
  
  - `keys: :atoms`, will convert all keys to atoms when parsing
  - `keys: :strings`, will keep all keys as strings when parsing (default)
  - `filename: String.t`, will use the given name as the filename in errors
  """
  @spec parse(binary) :: {:ok, map} | {:error, term}
  @spec parse(binary, opts) :: {:ok, map} | {:error, term}
  defdelegate parse(bin, opts \\ []), to: __MODULE__.Parser
  
  @doc """
  Parse the file at the given path as TOML
  
  Takes same options as `parse/2`
  """
  @spec parse_file(binary) :: {:ok, map} | {:error, term}
  @spec parse_file(binary, opts) :: {:ok, map} | {:error, term}
  defdelegate parse_file(path, opts \\ []), to: __MODULE__.Parser
  
  @doc """
  Parse the given stream as TOML.

  Takes same options as `parse/2`
  """
  @spec parse_stream(Enumerable.t) :: {:ok, map} | {:error, term}
  @spec parse_stream(Enumerable.t, opts) :: {:ok, map} | {:error, term}
  defdelegate parse_stream(stream, opts \\ []), to: __MODULE__.Parser
end
