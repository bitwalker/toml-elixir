defmodule Toml.Document do
  @moduledoc false
  
  # This module/struct is used for managing the state of the decoded TOML
  # document, namely constructing the map which is ultimately returned by
  # the decoder, and validating the mutations of the document. All operations
  # either return a valid document or an error.

  defstruct [:keys, :comments, :open_table, :comment_stack, :keytype]
  
  # A key is either binary or atom depending on the decoder option value
  @type key :: binary | atom | term
  
  # A value is the fully decoded value from the TOML
  @type value :: %{key => value}
               | {:table_array, [%{key => value}]}
               | number
               | binary
               | NaiveDateTime.t
               | DateTime.t
               | Date.t
               | Time.t
               | [value]
               
  # A keypath is a list of keys, they are all of the same key type
  @type keypath :: list(binary) | list(atom) | list(term)

  @type t :: %__MODULE__{
    keys: %{key => value},
    comments: %{keypath => binary},
    open_table: keypath,
    comment_stack: [binary],
    keytype: :strings | :atoms | :atoms! | ((binary) -> term)
  }
  
  @compile inline: [key: 3, keys: 2, comment: 2, open: 2, close: 1, to_result: 1]
  
  @doc """
  Create a new empty TOML document
  """
  @spec new(Toml.opts) :: t
  def new(opts) when is_list(opts) do
    %__MODULE__{
      keys: %{}, 
      comments: %{}, 
      open_table: nil,
      comment_stack: [],
      keytype: Keyword.get(opts, :keys, :strings),
    }
  end
  
  @doc """
  Convert the given TOML document to a plain map.
  """
  @spec to_map(t) :: {:ok, map} | {:error, term}
  def to_map(%__MODULE__{keys: keys, keytype: type}) do
    {:ok, to_map2(keys, to_key_fun(type))}
  catch
    :throw, {:error, _} = err ->
      err
  end
  defp to_map2(%_{} = s, _), do: s
  defp to_map2(m, nil) when is_map(m) do
    for {k, v} <- m, into: %{}, do: {k, to_map2(v, nil)}
  end
  defp to_map2(m, fun) when is_map(m) and is_function(fun, 1) do
    for {k, v} <- m, into: %{} do
      {fun.(k), to_map2(v, fun)}
    end
  end
  defp to_map2(l, keytype) when is_list(l) do
    for item <- l do
      to_map2(item, keytype)
    end
  end
  defp to_map2({:table_array, l}, keytype), do: to_map2(Enum.reverse(l), keytype)
  defp to_map2(v, _), do: v
  
  defp to_key_fun(:atoms), do: &to_atom/1
  defp to_key_fun(:atoms!), do: &to_existing_atom/1
  defp to_key_fun(:strings), do: nil
  defp to_key_fun(fun) when is_function(fun, 1), do: fun
  
  defp to_atom(<<c::utf8, _::binary>> = key) when c >= ?A and c <= ?Z do
    Module.concat([key])
  end
  defp to_atom(key), do: String.to_atom(key)
  
  defp to_existing_atom(<<c::utf8, _::binary>> = key) when c >= ?A and c <= ?Z do
    Module.concat([String.to_existing_atom(key)])
  rescue
    ArgumentError ->
      throw {:error, {:keys, {:non_existing_atom, key}}}
  end
  defp to_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError ->
      throw {:error, {:keys, {:non_existing_atom, key}}}
  end
  
  @doc """
  Push a comment on a stack containing lines of comments applying to some element.
  Comments are collected and assigned to key paths when a key is set, table created, etc.
  """
  def push_comment(%__MODULE__{comment_stack: cs} = doc, comment) do
    %__MODULE__{doc | comment_stack: [comment | cs]}
  end
  
  @doc """
  Push a value for a key into the TOML document.

  This operation is used when any key/value pair is set, and table or table array is defined.
  
  Based on the key the type of the value provided, the behavior of this function varies, as validation
  as performed as part of setting the key, to ensure that redefining keys is prohibited, but that setting
  child keys of existing tables is allowed. Table arrays considerably complicate this unfortunately.
  """
  def push_key(%__MODULE__{keys: ks} = doc, [key], value) when is_map(value) and map_size(value) == 0 do
    # New table
    keypath = [key]
    case Map.get(ks, key) do
      nil ->
        doc
        |> key(key, %{})
        |> comment(keypath)
        |> open(keypath)
        |> to_result()
      exists when is_map(exists) ->
        cond do
          map_size(exists) == 0 ->
            # Redefinition
            key_exists!(keypath)
          Enum.all?(exists, fn {_, v} when is_map(v) -> true; _ -> false end) ->
            # All keys are sub-tables, we'll allow this
            doc 
            |> comment(keypath) 
            |> open(keypath)
            |> to_result()
        end
      _exists ->
        key_exists!(keypath)
    end
  end
  def push_key(%__MODULE__{keys: ks} = doc, [key], value) when is_map(value) do
    # Pushing an inline table
    keypath = [key]
    case push_key_into_table(ks, [key], value) do
      {:ok, ks} ->
        doc
        |> keys(ks)
        |> comment(keypath)
        |> close()
        |> to_result()
      {:error, :key_exists} ->
        key_exists!(keypath)
    end
  end
  def push_key(%__MODULE__{keys: ks} = doc, [key], {:table_array, _} = value) do
    keypath = [key]
    case push_key_into_table(ks, [key], value) do
      {:ok, ks} ->
        doc
        |> keys(ks)
        |> comment(keypath)
        |> close()
        |> to_result()
      {:error, :key_exists} ->
        key_exists!(keypath)
    end
  end
  def push_key(%__MODULE__{keys: ks, open_table: nil} = doc, [key], value) do
    # Pushing a key/value pair at the root level of the document
    keypath = [key]
    if Map.has_key?(ks, key) do
      key_exists!(keypath)
    end
    
    doc
    |> key(key, value)
    |> comment(keypath)
    |> close()
    |> to_result()
  end
  def push_key(%__MODULE__{keys: ks, open_table: opened} = doc, [key], value) do
    # Pushing a key/value pair when a table is open
    keypath = opened ++ [key]
    case push_key_into_table(ks, keypath, value) do
      {:ok, ks} ->
        doc
        |> keys(ks)
        |> comment(keypath)
        |> to_result()
      {:error, :key_exists} ->
        key_exists!(keypath)
    end
  end
  def push_key(%__MODULE__{keys: ks} = doc, keypath, value) when is_list(keypath) and is_map(value) do
    # Pushing a multi-part key with an inline table value
    case push_key_into_table(ks, keypath, value) do
      {:ok, ks} ->
        doc
        |> keys(ks)
        |> comment(keypath)
        |> open(keypath)
        |> to_result()
      {:error, :key_exists} ->
        key_exists!(keypath)
    end
  end
  def push_key(%__MODULE__{keys: ks} = doc, keypath, value) when is_list(keypath) do
    # Pushing a multi-part key with a plain value
    case push_key_into_table(ks, keypath, value) do
      {:ok, ks} ->
        opening = Enum.take(keypath, length(keypath) - 1)
        doc
        |> keys(ks)
        |> comment(keypath)
        |> open(opening)
        |> to_result()
      {:error, :key_exists} ->
        key_exists!(keypath)
    end
  end
  
  @doc """
  Starts a new table and sets the context for subsequent key/values
  """
  def push_table(%__MODULE__{} = doc, keypath) do
    with {:ok, doc} = push_key(%__MODULE__{doc | open_table: nil}, keypath, %{}) do
      # We're explicitly opening a new table
      doc |> open(keypath) |> to_result()
    end
  end
  
  @doc """
  Starts a new array of tables and sets the context for subsequent key/values
  """
  def push_table_array(%__MODULE__{} = doc, keypath) do
    with {:ok, doc} = push_key(%__MODULE__{doc | open_table: nil}, keypath, {:table_array, []}) do
      # We're explicitly opening a new table
      doc |> open(keypath) |> to_result()
    end
  end

  @doc false
  def push_key_into_table({:table_array, array}, keypath, value) when is_map(value) do
    case array do
      [] ->
        {:ok, {:table_array, [value]}}
      [h | t] when is_map(h) ->
        case push_key_into_table(h, keypath, value) do
          {:ok, h2} ->
            {:ok, {:table_array, [h2 | t]}}
          {:error, _} = err ->
            err
        end
    end
  end
  def push_key_into_table({:table_array, array}, keypath, value) do
    # Adding key/value to last table item
    case array do
      [] ->
        case push_key_into_table(%{}, keypath, value) do
          {:ok, item} ->
            {:ok, {:table_array, [item]}}
          {:error, _} = err ->
            err
        end
      [h | t] when is_map(h) ->
        case push_key_into_table(h, keypath, value) do
          {:ok, h2} ->
            {:ok, {:table_array, [h2 | t]}}
          {:error, _} = err ->
            err
        end
    end
  end
  def push_key_into_table(ts, [key], value) do
    # Reached final table
    case Map.get(ts, key) do
      nil ->
        {:ok, Map.put(ts, key, value)}
      {:table_array, items} when is_list(items) and is_tuple(value) and elem(value, 0) == :table_array ->
        # Appending to table array
        {:ok, Map.put(ts, key, {:table_array, [%{} | items]})}
      {:table_array, items} when is_list(items) and is_map(value) ->
        # Pushing into table array
        {:ok, Map.put(ts, key, {:table_array, [value | items]})}
      exists when is_map(exists) and is_map(value) ->
        Enum.reduce(value, exists, fn {k, v}, acc -> 
          case push_key_into_table(acc, [k], v) do
            {:ok, acc2} ->
              acc2
            {:error, _} = err ->
              throw err
          end
        end)
      _exists ->
        {:error, :key_exists}
    end
  catch
    :throw, {:error, _} = err ->
      err
  end
  def push_key_into_table(ts, [table | keypath], value) do
    result =
      case Map.get(ts, table) do
        nil ->
          push_key_into_table(%{}, keypath, value)
        child ->
          push_key_into_table(child, keypath, value)
      end
    case result do
      {:ok, child} ->
        {:ok, Map.put(ts, table, child)}
      {:error, _} = err ->
        err
    end
  end
  
  defp key_exists!(keypath) do
    joined = Enum.join(keypath, ".")
    error!({:key_exists, joined})
  end

  defp error!(reason), 
    do: throw({:error, {:invalid_toml, reason}})
  
  defp get_comment(%__MODULE__{comment_stack: stack} = doc) do
    comment =
      stack
      |> Enum.reverse
      |> Enum.join("\n")
    {comment, %__MODULE__{doc | comment_stack: []}}
  end
  
  defp key(%__MODULE__{keys: keys} = doc, key, value) do
    %__MODULE__{doc | keys: Map.put(keys, key, value)}
  end

  defp keys(%__MODULE__{} = doc, keys) do
    %__MODULE__{doc | keys: keys}
  end
  
  defp comment(%__MODULE__{comments: cs} = doc, key) do
    {comment, doc} = get_comment(doc)
    if byte_size(comment) > 0 do
      %__MODULE__{doc | comment_stack: [], comments: Map.put(cs, key, comment)}
    else
      %__MODULE__{doc | comment_stack: []}
    end
  end
  
  defp open(%__MODULE__{} = doc, key) do
    %__MODULE__{doc | open_table: key}
  end
  
  defp close(%__MODULE__{} = doc) do
    %__MODULE__{doc | open_table: nil}
  end
  
  defp to_result(%__MODULE__{} = doc) do
    {:ok, doc}
  end
end
