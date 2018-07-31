defmodule Toml.Lexer.String do
  @moduledoc false
  
  # This module manages the complexity of lexing quoted and literal
  # strings as defined by the TOML spec.
  
  import Toml.Lexer.Guards
  
  def lex(<<>>, skip, lines), 
    do: {:error, :unexpected_eof, skip, lines}
  def lex(<<?\', ?\', ?\', rest::binary>>, skip, lines) do
    {rest, skip, lines} = trim_newline(rest, skip+3, lines)
    lex_literal(:multi, rest, skip, [], lines)
  end
  def lex(<<?\', ?\', rest::binary>>, skip, lines),
    do: {:ok, rest, {:string, skip+2, <<>>, lines}}
  def lex(<<?\', rest::binary>>, skip, lines),
    do: lex_literal(:single, rest, skip+1, [], lines)
  def lex(<<?\", ?\", ?\", rest::binary>>, skip, lines) do
    {rest, skip, lines} = trim_newline(rest, skip+3, lines)
    lex_quoted(:multi, rest, skip, [], lines)
  end
  def lex(<<?\", ?\", rest::binary>>, skip, lines),
    do: {:ok, rest, {:string, skip+2, <<>>, lines}}
  def lex(<<?\", rest::binary>>, skip, lines),
    do: lex_quoted(:single, rest, skip+1, [], lines)

  
  defp lex_literal(_type, <<>>, skip, _acc, lines),
    do: {:error, :unclosed_quote, skip, lines}
  # Disallow newlines in single-line literals
  defp lex_literal(:single, <<?\r, ?\n, _::binary>>, skip, _acc, lines), 
    do: {:error, :unexpected_newline, skip+1, lines}
  defp lex_literal(:single, <<?\n, _::binary>>, skip, _acc, lines), 
    do: {:error, :unexpected_newline, skip+1, lines}
  defp lex_literal(type, <<?\r, ?\n, rest::binary>>, skip, acc, lines),
    do: lex_literal(type, rest, skip+2, [?\n | acc], lines+1)
  defp lex_literal(type, <<?\n, rest::binary>>, skip, acc, lines),
    do: lex_literal(type, rest, skip+1, [?\n | acc], lines+1)
  # Closing quotes
  defp lex_literal(:single, <<?\', rest::binary>>, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, rest, {:string, skip+1, bin, lines}}
  end
  defp lex_literal(:multi, <<?\', ?\', ?\', rest::binary>>, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, rest, {:multiline_string, skip+3, bin, lines}}
  end
  # Eat next character in string
  defp lex_literal(type, <<c::utf8, rest::binary>>, skip, acc, lines), 
    do: lex_literal(type, rest, skip+1, [c | acc], lines)
  
  defp lex_quoted(_type, <<>>, skip, _acc, lines),
    do: {:error, :unclosed_quote, skip, lines}
  # Disallow newlines in single-line strings
  defp lex_quoted(:single, <<?\r, ?\n, _::binary>>, skip, _acc, lines), 
    do: {:error, :unexpected_newline, skip+1, lines}
  defp lex_quoted(:single, <<?\n, _::binary>>, skip, _acc, lines), 
    do: {:error, :unexpected_newline, skip+1, lines}
  defp lex_quoted(type, <<?\r, ?\n, rest::binary>>, skip, acc, lines),
    do: lex_quoted(type, rest, skip+2, [?\n | acc], lines+1)
  defp lex_quoted(type, <<?\n, rest::binary>>, skip, acc, lines),
    do: lex_quoted(type, rest, skip+1, [?\n | acc], lines+1)
  # Allowed escapes
  defp lex_quoted(type, <<?\\, ?\\, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+2, [?\\ | acc], lines)
  end
  defp lex_quoted(type, <<?\\, ?b, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+2, [?\b | acc], lines)
  end
  defp lex_quoted(type, <<?\\, ?d, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+2, [?\d | acc], lines)
  end
  defp lex_quoted(type, <<?\\, ?f, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+2, [?\f | acc], lines)
  end
  defp lex_quoted(type, <<?\\, ?n, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+2, [?\n | acc], lines)
  end
  defp lex_quoted(type, <<?\\, ?r, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+2, [?\r | acc], lines)
  end
  defp lex_quoted(type, <<?\\, ?t, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+2, [?\t | acc], lines)
  end
  defp lex_quoted(type, <<?\\, ?\", rest::binary>>, skip, acc, lines), 
    do: lex_quoted(type, rest, skip+2, [?\" | acc], lines)
  defp lex_quoted(type, <<?\\, ?u, rest::binary>>, skip, acc, lines) do
    {char, rest, skip2} = unescape_unicode(rest)
    lex_quoted(type, rest, 2+skip+skip2, [char | acc], lines)
  catch
    :throw, {:invalid_unicode, _} = reason ->
      {:error, reason, skip, lines}
  end
  defp lex_quoted(type, <<?\\, ?U, rest::binary>>, skip, acc, lines) do
    {char, rest, skip2} = unescape_unicode(rest)
    lex_quoted(type, rest, 2+skip+skip2, [char | acc], lines)
  catch
    :throw, {:invalid_unicode, _} = reason ->
      {:error, reason, skip, lines}
  end
  # Allow escaping newlines in multi-line strings
  defp lex_quoted(:multi, <<?\\, ?\r, ?\n, rest::binary>>, skip, acc, lines) do
    {rest, skip, lines} = trim_whitespace(:quoted, rest, skip+3, lines+1)
    lex_quoted(:multi, rest, skip, acc, lines)
  end
  defp lex_quoted(:multi, <<?\\, ?\n, rest::binary>>, skip, acc, lines) do
    {rest, skip, lines} = trim_whitespace(:quoted, rest, skip+2, lines+1)
    lex_quoted(:multi, rest, skip, acc, lines)
  end
  # Bad escape
  defp lex_quoted(_type, <<?\\, char::utf8, _::binary>>, skip, _acc, lines) do
    {:error, {:invalid_escape, <<?\\, char::utf8>>}, skip, lines}
  end
  # Closing quotes
  defp lex_quoted(:multi, <<?\", ?\", ?\", rest::binary>>, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.chardata_to_string()
    {:ok, rest, {:multiline_string, skip+3, bin, lines}}
  end
  defp lex_quoted(:single, <<?\", rest::binary>>, skip, acc, lines) do
    bin = acc |> Enum.reverse() |> IO.chardata_to_string()
    {:ok, rest, {:string, skip+1, bin, lines}}
  end
  # Eat next character in string
  defp lex_quoted(type, <<c::utf8, rest::binary>>, skip, acc, lines) do
    lex_quoted(type, rest, skip+1, [c | acc], lines)
  end

  defp trim_newline(<<?\r, ?\n, rest::binary>>, skip, lines), do: {rest, skip+2, lines+1}
  defp trim_newline(<<?\n, rest::binary>>, skip, lines), do: {rest, skip+1, lines+1}
  defp trim_newline(rest, skip, lines), do: {rest, skip, lines}
  
  # Trims whitespace (tab, space) up until next non-whitespace character,
  # or until closing delimiter for given string type. Only allowed with mulit-line strings.
  defp trim_whitespace(type, <<c::utf8, rest::binary>>, skip, lines) when is_whitespace(c) do
    trim_whitespace(type, rest, skip+1, lines)
  end
  defp trim_whitespace(:literal, <<?\', ?\', ?\', _::binary>> = rest, skip, lines), 
    do: {rest, skip, lines}
  defp trim_whitespace(:quoted, <<?\", ?\", ?\", _::binary>> = rest, skip, lines), 
    do: {rest, skip, lines}
  defp trim_whitespace(_type, rest, skip, lines), 
    do: {rest, skip, lines}
  
  defp unescape_unicode(<<n::4-binary, bin::binary>>) do
    case :erlang.binary_to_integer(n, 16) do
      high when 0xD800 <= high and high <= 0xDBFF ->
        # surrogate pair
        case bin do
          <<?\\, ?u, n2::4-binary, bin2::binary>> ->
            case :erlang.binary_to_integer(n2, 16) do
              low when 0xDC00 <= low and low <= 0xDFFF ->
                <<u::utf16>> = <<high::16, low::16>>
                {<<u::utf8>>, bin2, 4 + 6}
              _ ->
                bad_unicode!(n)
            end
          _ -> 
            bad_unicode!(n)
        end
      # second part of surrogate pair (without first part)
      u when 0xDC00 <= u and u <= 0xDFFF and u < 0 ->
        bad_unicode!(n)
      u ->
        {<<u::utf8>>, bin, 4}
    end
  catch 
    :error, :badarg -> 
      bad_unicode!(n)
  end
  defp unescape_unicode(<<c, _::binary>>) do
    bad_unicode!(<<c>>)
  end
  
  defp bad_unicode!(byte) do
    if String.printable?(byte) do
      throw {:invalid_unicode, "#{inspect byte, base: :hex} ('#{byte}')"}
    else
      throw {:invalid_unicode, "#{inspect byte, base: :hex}"}
    end
  end
end
