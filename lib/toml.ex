defmodule Toml do
  @moduledoc File.read!(Path.join([__DIR__, "..", "README.md"]))

  @doc """
  Parse the given binary as TOML content
  """
  @spec parse(binary) :: {:ok, map} | {:error, term}
  @spec parse(binary, String.t) :: {:ok, map} | {:error, term}
  defdelegate parse(bin, filename \\ "nofile"), to: __MODULE__.Parser
  
  @doc """
  Parse the file at the given path as TOML
  """
  @spec parse_file(binary) :: {:ok, map} | {:error, term}
  defdelegate parse_file(path), to: __MODULE__.Parser
  
  @doc """
  Parse the given stream as TOML.
  """
  @spec parse_stream(Enumerable.t) :: {:ok, map} | {:error, term}
  @spec parse_stream(Enumerable.t, String.t) :: {:ok, map} | {:error, term}
  defdelegate parse_stream(stream, filename \\ "nofile"), to: __MODULE__.Parser
end
