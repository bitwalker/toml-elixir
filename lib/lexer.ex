defmodule Toml.Lexer do
  @moduledoc false
  
  import __MODULE__.Guards

  defstruct [:pid]
  
  # The type of the token
  @type type :: :whitespace
              | :newline
              | :comment
              | :digits
              | :hex
              | :octal
              | :binary
              | :alpha
              | non_neg_integer
  # The number of bytes in the input to skip to reach the beginning of the token
  @type skip :: non_neg_integer
  # The data representation of a token (either size, a character, or string)
  @type data :: non_neg_integer | binary
  # The line number of the token
  @type lines :: non_neg_integer
  # The full shape of a token
  @type token :: {type, skip, data, lines}
  
  @doc """
  Creates a new Lexer with the given binary content.
  
  The lexer is a process, which manages the state of the lexer,
  and provides the following benefits:

  - Only lexes content as the decoder walks the document, minimizing
    the work performed, and resources (i.e. memory) used.
  - Allows pushing an arbitrary tokens back on the stack, allowing the
    decoder to "rewind" the lexer and try an alternative path.
  - Lexing the next token happens concurrently with the decoder handling the last token
  
  Currently, the lexer will build up strings for most tokens and send them back to
  the decoder, since these are running in separate processes, this means all string data
  contained in the tokens is copied. For some tokens, like comments, the lexer will send
  only the token type (e.g. `:comment`), and indexes into the original input, so that the
  content can be extracted only when needed, and in the most efficient manner possible. In
  the future, the lexer will do this will all tokens, allowing us to only make copies or store
  references into the original input when absolutely needed. We do not do this currently, as
  strings in TOML have escapes, which need to be unescaped during parsing. This could be deferred
  and done in the decoder, but is not done so right now.
  
  Returns `{:ok, %#{__MODULE__}{}}`.
  """
  def new(content) when is_binary(content) do
    with {:ok, pid} <- :proc_lib.start_link(__MODULE__, :init, [self(), content]) do
      {:ok, %__MODULE__{pid: pid}}
    end
  end
  
  @doc """
  Pops the next token from the lexer. This advances the lexer to the next token.
  """
  def pop(%__MODULE__{pid: pid}) when is_pid(pid), 
    do: server_call(pid, :pop)
    
  @doc """
  Advances the lexer to the next token, without returning the current token on the stack,
  effectively skipping the current token.
  """
  def advance(%__MODULE__{pid: pid}) when is_pid(pid),
    do: server_call(pid, :advance)

  @doc """
  Peeks at the next token the lexer will return from `pop/1`.

  Always returns the same result until the lexer advances.
  """
  def peek(%__MODULE__{pid: pid}) when is_pid(pid), 
    do: server_call(pid, :peek)

  @doc """
  Pushes a token back on the lexer's stack.

  You may push as many tokens back on the stack as desired.
  """
  def push(%__MODULE__{pid: pid}, {_type, _skip, _data, _lines} = token) when is_pid(pid), 
    do: server_call(pid, {:push, token})
    
  @doc """
  Terminates the lexer process.
  """
  def stop(%__MODULE__{pid: pid}) when is_pid(pid) do
    if Process.alive?(pid) do
      server_call(pid, :stop)
    else
      :ok
    end
  end
  
  @doc """
  Converts the lexer in to a `Stream`. Not currently used.
  """
  def stream(%__MODULE__{} = lexer) do
    Stream.resource(
      fn -> {lexer, false, false} end,
      fn 
        {_lexer, true, _error?} = acc -> 
          {:halt, acc}
        {_lexer, _eof?, true} = acc ->
          {:halt, acc}
        {lexer, false, false} ->
          case pop(lexer) do
            {:error, _, _, _} = err ->
              {[err], {lexer, false, true}}
            {:ok, {:eof, _, _, _}} = ok ->
              {[ok], {lexer, true, false}}
            {:ok, _} = ok ->
              {[ok], {lexer, false, false}}
          end
      end,
      fn {lexer, _, _} -> stop(lexer) end
    )
  end

  ## Private
  
  def init(parent, {:stream, stream}) do
    init(parent, Enum.into(stream, <<>>))
  end
  def init(parent, data) do
    Process.flag(:trap_exit, true)
    :proc_lib.init_ack(parent, {:ok, self()})
    lex(parent, :sys.debug_options([]), data, 0, 1, [])
  end
  
  # If an error is on the stack keep it there unless we push a valid token back on
  defp lex(parent, debug, data, skip, lines, {:error, _, _, _} = err) do
    receive do
      {:EXIT, ^parent, reason} ->
        exit(reason)
      {from, :stop} ->
        send(from, {self(), :ok})
        exit(:normal)
      {from, {:push, {_type, _tskip, _tsize, _tline} = token}} ->
        send(from, {self(), :ok})
        lex(parent, debug, data, skip, lines, [token])
      {from, op} when op in [:pop, :peek, :advance] ->
        send(from, {self(), err})
        lex(parent, debug, data, skip, lines, err)
    end
  end
  defp lex(parent, debug, data, skip, lines, []) do
    case do_lex(data, skip, lines) do
      {:error, _, _, _} = err ->
        lex(parent, debug, data, skip, lines, err)
      {:ok, data, {_type, skip, _size, lines} = token} ->
        lex(parent, debug, data, skip, lines, [token])
    end
  end
  defp lex(parent, debug, data, skip, lines, [token | stack] = ostack) do
    receive do
      {:EXIT, ^parent, reason} ->
        exit(reason)
      {from, :stop} ->
        send(from, {self(), :ok})
        exit(:normal)
      {from, :pop} ->
        send(from, {self(), {:ok, token}})
        lex(parent, debug, data, skip, lines, stack)
      {from, :advance} ->
        send(from, {self(), :ok})
        lex(parent, debug, data, skip, lines, stack)
      {from, :peek} ->
        send(from, {self(), {:ok, token}})
        lex(parent, debug, data, skip, lines, ostack)
      {from, {:push, pushed}} ->
        send(from, {self(), :ok})
        lex(parent, debug, data, skip, lines, [pushed | ostack])
    end
  end
  
  defp do_lex(<<>> = data, skip, lines), 
    do: {:ok, data, {:eof, skip, 0, lines}}
  defp do_lex(<<?\#, rest::binary>>, skip, lines), 
    do: lex_comment(rest, skip+1, 0, lines)
  defp do_lex(<<?\r, ?\n, rest::binary>>, skip, lines),
    do: {:ok, rest, {:newline, skip+2, 0, lines+1}}
  defp do_lex(<<?\n, rest::binary>>, skip, lines),
    do: {:ok, rest, {:newline, skip+1, 0, lines+1}}
  defp do_lex(<<c::utf8, rest::binary>>, skip, lines) when is_whitespace(c),
    do: lex_whitespace(rest, skip+1, lines)
  defp do_lex(<<"true", rest::binary>>, skip, lines),
    do: {:ok, rest, {true, skip+4, 0, lines}}
  defp do_lex(<<"false", rest::binary>>, skip, lines),
    do: {:ok, rest, {false, skip+5, 0, lines}}
  defp do_lex(<<?=, rest::binary>>, skip, lines),
    do: {:ok, rest, {?=, skip+1, 0, lines}}
  defp do_lex(<<?., rest::binary>>, skip, lines),
    do: {:ok, rest, {?., skip+1, 0, lines}}
  defp do_lex(<<?\[, rest::binary>>, skip, lines),
    do: {:ok, rest, {?\[, skip+1, 0, lines}}
  defp do_lex(<<?\], rest::binary>>, skip, lines),
    do: {:ok, rest, {?\], skip+1, 0, lines}}
  defp do_lex(<<?\{, rest::binary>>, skip, lines),
    do: {:ok, rest, {?\{, skip+1, 0, lines}}
  defp do_lex(<<?\}, rest::binary>>, skip, lines),
    do: {:ok, rest, {?\}, skip+1, 0, lines}}
  defp do_lex(<<?+, rest::binary>>, skip, lines),
    do: {:ok, rest, {?+, skip+1, 0, lines}}
  defp do_lex(<<?-, rest::binary>>, skip, lines),
    do: {:ok, rest, {?-, skip+1, 0, lines}}
  defp do_lex(<<?:, rest::binary>>, skip, lines),
    do: {:ok, rest, {?:, skip+1, 0, lines}}
  defp do_lex(<<?,, rest::binary>>, skip, lines),
    do: {:ok, rest, {?,, skip+1, 0, lines}}
  defp do_lex(<<?_, rest::binary>>, skip, lines),
    do: {:ok, rest, {?_, skip+1, 0, lines}}
  defp do_lex(<<?0, ?x, c::utf8, rest::binary>>, skip, lines) when is_hex(c),
    do: lex_hex(rest, skip+3, [c], lines)
  defp do_lex(<<?0, ?o, c::utf8, rest::binary>>, skip, lines) when is_octal(c),
    do: lex_octal(rest, skip+3, [c], lines)
  defp do_lex(<<?0, ?b, c::utf8, rest::binary>>, skip, lines) when is_bin(c),
    do: lex_binary(rest, skip+3, [c], lines)
  defp do_lex(<<c::utf8, _::binary>> = data, skip, lines) when is_quote(c),
    do: __MODULE__.String.lex(data, skip, lines)
  defp do_lex(<<c::utf8, rest::binary>>, skip, lines) when is_digit(c),
    do: lex_digits(rest, skip+1, [c], lines)
  defp do_lex(<<c::utf8, rest::binary>>, skip, lines) when is_alpha(c),
    do: lex_alpha(rest, skip+1, [c], lines)
  defp do_lex(<<c::utf8, _::binary>>, skip, lines),
    do: {:error, {:invalid_char, <<c::utf8>>}, skip+1, lines}
  
  defp lex_whitespace(<<c::utf8, rest::binary>>, skip, lines) when is_whitespace(c),
    do: lex_whitespace(rest, skip+1, lines)
  defp lex_whitespace(rest, skip, lines),
    do: {:ok, rest, {:whitespace, skip, 0, lines}}
  
  defp lex_comment(<<?\r, ?\n, rest::binary>>, skip, size, lines), 
    do: {:ok, rest, {:comment, skip+2, size, lines+1}}
  defp lex_comment(<<?\n, rest::binary>>, skip, size, lines),
    do: {:ok, rest, {:comment, skip+1, size, lines+1}}
  defp lex_comment(<<_::utf8, rest::binary>>, skip, size, lines), 
    do: lex_comment(rest, skip+1, size+1, lines)
  defp lex_comment(<<>> = rest, skip, size, lines),
    do: {:ok, rest, {:comment, skip, size, lines}}
    
  defp lex_digits(<<c::utf8, rest::binary>>, skip, acc, lines) when is_digit(c),
    do: lex_digits(rest, skip+1, [c | acc], lines)
  defp lex_digits(rest, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, rest, {:digits, skip, bin, lines}}
  end
    
  defp lex_hex(<<c::utf8, rest::binary>>, skip, acc, lines) when is_hex(c),
    do: lex_hex(rest, skip+1, [c | acc], lines)
  defp lex_hex(rest, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, rest, {:hex, skip, bin, lines}}
  end

  defp lex_octal(<<c::utf8, rest::binary>>, skip, acc, lines) when is_octal(c),
    do: lex_octal(rest, skip+1, [c | acc], lines)
  defp lex_octal(rest, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, rest, {:octal, skip, bin, lines}}
  end

  defp lex_binary(<<c::utf8, rest::binary>>, skip, acc, lines) when is_bin(c),
    do: lex_binary(rest, skip+1, [c | acc], lines)
  defp lex_binary(rest, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, rest, {:binary, skip, bin, lines}}
  end
    
  defp lex_alpha(<<c::utf8, rest::binary>>, skip, acc, lines) when is_alpha(c),
    do: lex_alpha(rest, skip+1, [c | acc], lines)
  defp lex_alpha(rest, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, rest, {:alpha, skip, bin, lines}}
  end
  
  defp server_call(pid, msg) do
    ref = Process.monitor(pid)
    send(pid, {self(), msg})
    receive do
      {:DOWN, ^ref, _type, _pid, info} ->
        {:error, info}
      {^pid, reply} ->
        Process.demonitor(ref, [:flush])
        reply
    end
  end
end
