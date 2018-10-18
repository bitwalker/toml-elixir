defmodule Toml.Provider do
  @moduledoc """
  This module provides an implementation of Distilery's configuration provider
  behavior, so that TOML files can be used for configuration in releases.

  ## Usage

  Add the following to your `rel/config.exs`

      release :myapp do
        # ...snip...
        set config_providers: [
          {Toml.Provider, [path: "${XDG_CONFIG_DIR}/myapp.toml", transforms: [...]]}
        ]
      end

  This will result in `Toml.Provider` being invoked during boot, at which point it
  will evaluate the given path and read the TOML file it finds. If one is not
  found, or is not accessible, the provider will raise an error, and the boot
  sequence will terminate unsuccessfully. If it succeeds, it persists settings in
  the file to the application environment (i.e. you access it via
  `Application.get_env/2`).

  The config provider expects a certain format to the TOML file, namely that
  keys at the root of the document are tables which correspond to applications
  which need to be configured. If it encounters keys at the root of the document
  which are not tables, they are ignored.

  ## Options

  The same options that `Toml.parse/2` accepts are able to be provided to `Toml.Provider`,
  but there are two main differences:

    * `:path` (required) - sets the path to the TOML file to load config from
    * `:keys` - defaults to `:atoms`, but can be set to `:atoms!` if desired, all other 
      key types are ignored, as it results in an invalid config structure

  """

  @doc false
  def init(opts) when is_list(opts) do
    path = Keyword.fetch!(opts, :path)

    opts =
      case Keyword.get(opts, :keys) do
        a when a in [:atoms, :atoms!] ->
          opts

        _ ->
          Keyword.put(opts, :keys, :atoms)
      end

    with {:ok, expanded} <- expand_path(path),
         map = Toml.decode_file!(expanded, opts),
         keyword when is_list(keyword) <- to_keyword(map) do
      persist(keyword)
    else
      {:error, reason} ->
        exit(reason)
    end
  end

  @doc false
  def get([app | keypath]) do
    config = Application.get_all_env(app)

    case get_in(config, keypath) do
      nil ->
        nil

      val ->
        {:ok, val}
    end
  end

  defp persist(keyword) when is_list(keyword) do
    # For each app
    for {app, app_config} <- keyword do
      # Get base config
      base = Application.get_all_env(app)
      # Merge this app's TOML config over the base config
      merged = deep_merge(base, app_config)
      # Persist key/value pairs for this app
      for {k, v} <- merged do
        Application.put_env(app, k, v, persistent: true)
      end
    end

    :ok
  end

  # At the top level, convert the map to a keyword list of keyword lists
  # Keys with no children (i.e. keys which are not tables) are dropped
  defp to_keyword(map) when is_map(map) do
    for {k, v} <- map, v2 = to_keyword2(v), is_list(v2), into: [] do
      {k, v2}
    end
  end

  # For all other values, convert tables to keywords
  defp to_keyword2(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {k, to_keyword2(v)} end)
  end

  # And leave all other values untouched
  defp to_keyword2(term), do: term

  defp deep_merge(a, b) when is_list(a) and is_list(b) do
    if Keyword.keyword?(a) and Keyword.keyword?(b) do
      Keyword.merge(a, b, &deep_merge/3)
    else
      b
    end
  end

  defp deep_merge(_k, a, b) when is_list(a) and is_list(b) do
    if Keyword.keyword?(a) and Keyword.keyword?(b) do
      Keyword.merge(a, b, &deep_merge/3)
    else
      b
    end
  end

  defp deep_merge(_k, a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, &deep_merge/3)
  end

  defp deep_merge(_k, _a, b), do: b

  def expand_path(path) when is_binary(path) do
    case expand_path(path, <<>>) do
      {:ok, p} ->
        {:ok, Path.expand(p)}

      {:error, _} = err ->
        err
    end
  end

  defp expand_path(<<>>, acc),
    do: {:ok, acc}

  defp expand_path(<<?$, ?\{, rest::binary>>, acc) do
    case expand_var(rest) do
      {:ok, var, rest} ->
        expand_path(rest, acc <> var)

      {:error, _} = err ->
        err
    end
  end

  defp expand_path(<<c::utf8, rest::binary>>, acc) do
    expand_path(rest, <<acc::binary, c::utf8>>)
  end

  defp expand_var(bin),
    do: expand_var(bin, <<>>)

  defp expand_var(<<>>, _acc),
    do: {:error, :unclosed_var_expansion}

  defp expand_var(<<?\}, rest::binary>>, acc),
    do: {:ok, System.get_env(acc) || "", rest}

  defp expand_var(<<c::utf8, rest::binary>>, acc) do
    expand_var(rest, <<acc::binary, c::utf8>>)
  end
end
