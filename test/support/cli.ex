defmodule Toml.CLI do
  @moduledoc false

  defstruct [:callback, :input, :argv, :opts]

  def main(args) do
    opts = parse_args!(args)
    opts.callback.(opts)
    System.halt(0)
  end

  ## Convert
  # Perform conversion from TOML content to other formats
  # Currently only supports JSON

  defp convert(%__MODULE__{argv: argv} = config) do
    aliases = [f: :file]
    flags = [file: :string, stdin: :boolean, format: :string, help: :boolean]
    {opts, _} = OptionParser.parse!(argv, aliases: aliases, strict: flags)
    # Show help if requested via flag
    if opts[:help] do
      help(%__MODULE__{config | argv: ["convert"]})
    end

    # Validate required opts
    if !(opts[:format] && (opts[:file] || opts[:stdin])) do
      warn!("You must provide both --format, and either --file or --stdin")
      help(%__MODULE__{config | argv: ["convert"]})
    end

    # Validate format
    if opts[:format] != "json" do
      fail!("Invalid conversion format '#{opts[:format]}'. Supported formats are: 'json'.")
    end

    input = input(opts)

    case parse(input) do
      {:ok, result} ->
        IO.puts([?\n, Jason.encode!(result, pretty: true)])

      {:error, _} = err ->
        fail!(err)
    end
  end

  ## Validate
  # Validate a TOML document

  defp validate(%__MODULE__{argv: argv} = config) do
    aliases = [f: :file]
    flags = [file: :string, stdin: :boolean, help: :boolean, quiet: :boolean]
    {opts, _} = OptionParser.parse!(argv, aliases: aliases, strict: flags)
    # Show help if requested
    if opts[:help] do
      help(%__MODULE__{config | argv: ["validate"]})
    end

    # Validate required opts
    if !(opts[:file] || opts[:stdin]) do
      warn!("You must provide either --file or --stdin")
      help(%__MODULE__{config | argv: ["validate"]})
    end

    # Validate
    quiet? = opts[:quiet]
    input = input(opts)

    case parse(input) do
      {:ok, _} ->
        :ok

      {:error, _} when quiet? ->
        System.halt(1)

      {:error, {:invalid_toml, reason}} when is_binary(reason) ->
        fail!(reason)
    end
  end

  # Determine TOML input from options
  defp input(opts) do
    if opts[:stdin] do
      IO.stream(:stdio, :line)
    else
      opts[:file]
    end
  end

  ## Help
  # Display global help, or command help

  defp help(%__MODULE__{} = config) do
    help(config.argv)
    System.halt(2)
  end

  defp help([]) do
    IO.puts("""
    toml - A utility program for TOML, written in Elixir

    Usage:
      toml [flags]
      toml [command] [flags]
      
    Available Commands:
      convert  Convert TOML content to another format.
      help     Show help
    """)
  end

  defp help(["convert" | _]) do
    IO.puts("""
    Converts TOML content to another format.

    Currently, only JSON is supported.

    Usage:
      toml convert [flags]
      
    Flags:
      -f, --file       Specify a file to convert
      --stdin          Read TOML content from standard input
      --format string  Specify the format to convert to
    """)
  end

  defp help(["validate" | _]) do
    IO.puts("""
    Validates TOML content.

    Exits with a status code of zero if valid, non-zero if invalid.

    Validation errors will be printed to standard error.

    Usage:
      toml validate [flags]
      
    Flags:
      -f, --file      Specify a file to validate
      --stdin         Read TOML content from standard input
      --quiet         Do not print errors, just exit
    """)
  end

  defp help(["help"]) do
    IO.puts("""
    Displays help for toml, or for a specific toml command.

    Usage:
      toml help
      toml help [command]
    """)
  end

  defp help(["help" | rest]) do
    help(rest)
  end

  defp help([command]) do
    warn!("Unknown command: #{command}")
    help([])
  end

  # Parse raw args to configuration struct
  defp parse_args!(args) do
    # When run under toml-test, we can't accept arguments
    if System.get_env("TOML_TEST") == "true" do
      %__MODULE__{callback: &convert/1, argv: ["--stdin", "--format", "json"], opts: []}
    else
      {opts, argv} = OptionParser.parse_head!(args, strict: [help: :boolean])

      if opts[:help] do
        %__MODULE__{callback: &help/1, opts: opts, argv: argv}
      else
        case argv do
          ["convert" | argv] ->
            %__MODULE__{callback: &convert/1, opts: opts, argv: argv}

          ["validate" | argv] ->
            %__MODULE__{callback: &validate/1, opts: opts, argv: argv}

          _ ->
            %__MODULE__{callback: &help/1, opts: opts, argv: argv}
        end
      end
    end
  end

  # Parse the given input with the appropriate parser
  defp parse(input) when is_binary(input),
    do: Toml.decode_file(input)

  defp parse(stream),
    do: Toml.decode_stream(stream)

  # Write an error to stderr and halt non-zero
  defp fail!({:error, reason}) when is_binary(reason) do
    IO.puts(:standard_error, reason)
    System.halt(1)
  end

  defp fail!({:error, reason}) do
    IO.puts(:standard_error, "Error: #{inspect(reason)}")
    System.halt(1)
  end

  # Write a warning to stderr
  defp warn!(msg) when is_binary(msg) do
    IO.puts(:standard_error, msg)
  end
end
