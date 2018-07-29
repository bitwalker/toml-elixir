defmodule Toml do
  @moduledoc File.read!(Path.join([__DIR__, "..", "README.md"]))
  
  @type opt :: {:keys, :atoms | :atoms! | :string}
             | {:filename, String.t}
  @type opts :: [opt]

  @doc """
  Decode the given binary as TOML content
  
  ## Options

  You can pass the following options to configure the decoder behavior:
  
    * `:filename` - pass a filename to use in error messages
    * `:keys` - controls how keys in the document are decoded. Possible values are:

      * `:strings` (default) - decodes keys as strings
      * `:atoms` - converts keys to atoms with `String.to_atom/1`
      * `:atoms!` - converts keys to atoms with `String.to_existing_atom/1`
      
  ## Decoding keys to atoms

  The `:atoms` option uses the `String.to_atom/1` call that can create atoms at runtime.
  Since the atoms are not garbage collected, this can pose a DoS attack vector when used
  on user-controlled data. It is recommended that if you either avoid converting to atoms,
  by using `keys: :strings`, or require known keys, by using the `keys: :atoms!` option, 
  which will cause decoding to fail if the key is not an atom already in the atom table.
  """
  @spec decode(binary) :: {:ok, map} | {:error, term}
  @spec decode(binary, opts) :: {:ok, map} | {:error, term}
  defdelegate decode(bin, opts \\ []), to: __MODULE__.Decoder
  
  @doc """
  Same as `decode/1`, but returns the document directly, or raises `Toml.Error` if it fails.
  """
  @spec decode!(binary) :: map | no_return
  @spec decode!(binary, opts) :: map | no_return
  def decode!(bin, opts \\ []) do
    case decode(bin, opts) do
      {:ok, result} ->
        result
      {:error, _} = err ->
        raise Toml.Error, err
    end
  end
  
  @doc """
  Decode the file at the given path as TOML
  
  Takes same options as `decode/2`
  """
  @spec decode_file(binary) :: {:ok, map} | {:error, term}
  @spec decode_file(binary, opts) :: {:ok, map} | {:error, term}
  defdelegate decode_file(path, opts \\ []), to: __MODULE__.Decoder
  
  @doc """
  Same as `decode_file/1`, but returns the document directly, or raises `Toml.Error` if it fails.
  """
  @spec decode_file!(binary) :: map | no_return
  @spec decode_file!(binary, opts) :: map | no_return
  def decode_file!(path, opts \\ []) do
    case decode_file(path, opts) do
      {:ok, result} ->
        result
      {:error, _} = err ->
        raise Toml.Error, err
    end
  end
  
  @doc """
  Decode the given stream as TOML.

  Takes same options as `decode/2`
  """
  @spec decode_stream(Enumerable.t) :: {:ok, map} | {:error, term}
  @spec decode_stream(Enumerable.t, opts) :: {:ok, map} | {:error, term}
  defdelegate decode_stream(stream, opts \\ []), to: __MODULE__.Decoder
  
  @doc """
  Same as `decode_stream/1`, but returns the document directly, or raises `Toml.Error` if it fails.
  """
  @spec decode_stream!(Enumerable.t) :: map | no_return
  @spec decode_stream!(Enumerable.t, opts) :: map | no_return
  def decode_stream!(stream, opts \\ []) do
    case decode_stream(stream, opts) do
      {:ok, result} ->
        result
      {:error, _} = err ->
        raise Toml.Error, err
    end
  end
end
