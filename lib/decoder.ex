defmodule Toml.Decoder do
  @moduledoc false
  
  alias Toml.Document
  alias Toml.Builder
  alias Toml.Lexer
  
  @compile :inline_list_funs
  @compile inline: [pop_skip: 2, peek_skip: 2,
                    iodata_to_str: 1, iodata_to_integer: 1, iodata_to_float: 1]
  
  @doc """
  Decodes a raw binary
  """
  @spec decode(binary, Toml.opts) :: {:ok, map} | {:error, term}
  def decode(bin, opts) when is_binary(bin) and is_list(opts) do
    filename = Keyword.get(opts, :filename, "nofile")
    {:ok, lexer} = Lexer.new(bin)
    try do
      with {:ok, %Document{} = doc} <- do_decode(lexer, bin, Builder.new(opts)),
           {:ok, _} = ok <- Document.to_map(doc) do
        ok
      else
        {:error, {:badarg, reason}} ->
          raise ArgumentError, reason
        {:error, {:keys, :non_existing_atom} = reason} ->
          {:error, {:invalid_toml, Toml.Error.format_reason(reason)}}
        {:error, reason, skip, lines} ->
          {:error, {:invalid_toml, format_error(reason, bin, filename, skip, lines)}}
        {:error, reason} ->
          {:error, {:invalid_toml, reason}}
      end
    catch
      :throw, {:error, {:invalid_toml, reason}} = err when is_binary(reason) ->
         err
      :throw, {:error, {:invalid_toml, reason}} ->
        {:error, {:invalid_toml, Toml.Error.format_reason(reason)}}
    after
      Lexer.stop(lexer)
    end
  end

  @doc """
  Decodes a stream
  """
  @spec decode_stream(Enumerable.t, Toml.opts) :: {:ok, map} | {:error, term}
  def decode_stream(stream, opts) do
    decode(Enum.into(stream, <<>>), opts)
  end
  
  @doc """
  Decodes a file
  """
  @spec decode_file(String.t, Toml.opts) :: {:ok, map} | {:error, term}
  def decode_file(path, opts) when is_binary(path) do
    opts =
      case Keyword.get(opts, :filename) do
        nil ->
          Keyword.put(opts, :filename, path)
        _ ->
          opts
      end
    with {:ok, bin} <- File.read(path) do
      decode(bin, opts)
    end
  end
  
  ## Decoder Implementation
  
  defp do_decode(_lexer, _original, {:error, _, _, _} = err), 
    do: err
  defp do_decode(lexer, original, doc) do
    case Lexer.pop(lexer) do
      {:error, _reason, _skip, _lines} = err ->
        err
      {:ok, {type, skip, data, lines}}->
        handle_token(lexer, original, doc, type, skip, data, lines)
    end
  end
  
  # Converts an error into a friendly, printable representation
  defp format_error(reason, original, filename, skip, lines) do
    msg = "#{Toml.Error.format_reason(reason)} in #{Path.relative_to_cwd(filename)} on line #{lines}"
    {ctx, pos} = seek_line(original, skip, lines)
    """
    #{msg}:
    
        #{ctx}
        #{String.duplicate(" ", pos+1)}^
    """
  end
  
  # Finds the line of context for display in a formatted error
  defp seek_line(original, skip, lines) do
    seek_line(original, original, 0, 0, skip, lines-1)
  end
  defp seek_line(original, rest, lastnl, from, len, 0) do
    case seek_to_eol(rest, 0) do
      0 ->
        {binary_part(original, lastnl, from-lastnl), from-lastnl}
      len_to_eol ->
        {binary_part(original, from, len_to_eol), len}
    end
  end
  defp seek_line(original, <<?\r, ?\n, rest::binary>>, lastnl, from, len, 1) when len <= 0 do
    # Content occurred on the last line right before the newline
    seek_line(original, rest, lastnl, from+2, 0, 0)
  end
  defp seek_line(original, <<?\r, ?\n, rest::binary>>, _, from, len, lines) do
    seek_line(original, rest, from+2, from+2, len-2, lines-1)
  end
  defp seek_line(original, <<?\n, _::binary>> = rest, lastnl, from, len, 1) when len <= 0 do
    # Content occurred on the last line right before the newline
    seek_line(original, rest, lastnl, from+1, 0, 0)
  end
  defp seek_line(original, <<?\n, rest::binary>>, _, from, len, lines) do
    seek_line(original, rest, from+1, from+1, len-1, lines-1)
  end
  defp seek_line(original, <<_::utf8, rest::binary>>, lastnl, from, len, lines) do
    seek_line(original, rest, lastnl, from+1, len-1, lines)
  end
  
  # Find the number of bytes to the end of the current line in the input
  defp seek_to_eol(<<>>, len), do: len
  defp seek_to_eol(<<?\r, ?\n, _::binary>>, len), do: len
  defp seek_to_eol(<<?\n, _::binary>>, len), do: len
  defp seek_to_eol(<<_::utf8, rest::binary>>, len) do
    seek_to_eol(rest, len+1)
  end
  
  # Skip top-level whitespace and newlines
  defp handle_token(lexer, original, doc, :whitespace, _skip, _data, _lines),
    do: do_decode(lexer, original, doc)
  defp handle_token(lexer, original, doc, :newline, _skip, _data, _lines),
    do: do_decode(lexer, original, doc)
  # Push comments on the comment stack
  defp handle_token(lexer, original, doc, :comment, skip, size, _lines) do
    comment = binary_part(original, skip-size, size)
    do_decode(lexer, original, Builder.push_comment(doc, comment))
  end
  # Handle valid top-level entities
  # - array of tables
  # - table
  # - key/value
  defp handle_token(lexer, original, doc, ?\[, skip, data, lines) do
    case peek_skip(lexer, [:whitespace]) do
      {:error, _, _, _} = err ->
        err
      {:ok, {?\[, _, _, _}} ->
        # Push opening bracket, second was peeked, so no need
        Lexer.push(lexer, {?\[, skip, data, lines})
        handle_table_array(lexer, original, doc)
      {:ok, {_, _, _, _}} ->
        Lexer.push(lexer, {?\[, skip, data, lines})
        handle_table(lexer, original, doc)
    end
  end
  defp handle_token(lexer, original, doc, type, skip, data, lines) 
  when type in [:digits, :alpha, :string] do
    Lexer.push(lexer, {type, skip, data, lines})
    with {:ok, key, _skip, _lines} <- key(lexer) do
      handle_key(lexer, original, doc, key)
    end
  end
  defp handle_token(lexer, original, doc, type, skip, _data, lines) when type in '-_' do
    handle_token(lexer, original, doc, :string, skip, <<type::utf8>>, lines)
  end
  # We're done
  defp handle_token(_lexer, _original, doc, :eof, _skip, _data, _lines) do
    {:ok, doc}
  end
  # Anything else at top-level is invalid
  defp handle_token(_lexer, _original, _doc, type, skip, data, lines) do
    {:error, {:invalid_token, {type, data}}, skip, lines}
  end
  
  defp handle_key(lexer, original, doc, key) do
    with {:ok, {?=, _, _, _}} <- pop_skip(lexer, [:whitespace]),
         {:ok, value} <- value(lexer),
         {:ok, doc} <- Builder.push_key(doc, key, value) do
      # Make sure key/value pairs are separated by a newline
      case peek_skip(lexer, [:whitespace]) do
        {:error, _, _, _} = err ->
          err
        {:ok, {:comment, _, _, _}} ->
          # Implies newline
          do_decode(lexer, original, doc)
        {:ok, {type, _, _, _}} when type in [:newline, :eof] ->
          do_decode(lexer, original, doc)
        {:ok, {type, skip, data, lines}} ->
          {:error, {:expected, :newline, {type, data}}, skip, lines}
      end
    else
      {:error, _, _, _} = err ->
        err
      {:ok, {type, skip, data, lines}} ->
        {:error, {:expected, ?=, {type, data}}, skip, lines}
    end
  end

  defp handle_table(lexer, original, doc) do
    # Guaranteed to have an open bracket
    with {:ok, {?\[, _, _, _}} <- pop_skip(lexer, [:whitespace]),
         {:ok, key, _line, _col} <- key(lexer),
         {:ok, {?\], _, _, _}} <- pop_skip(lexer, [:whitespace]),
         {:ok, doc} <- Builder.push_table(doc, key) do
      # Make sure table opening is followed by newline
      case peek_skip(lexer, [:whitespace]) do
        {:error, _, _, _} = err ->
          err
        {:ok, {:comment, _, _, _}} ->
          do_decode(lexer, original, doc)
        {:ok, {type, _, _, _}} when type in [:newline, :eof] ->
          do_decode(lexer, original, doc)
        {:ok, {type, skip, data, lines}} ->
          {:error, {:expected, :newline, {type, data}}, skip, lines}
      end
    else
      {:error, _, _, _} = err ->
        err
      {:ok, {type, skip, data, lines}} ->
        {:error, {:invalid_token, {type, data}}, skip, lines}
    end
  end
  
  defp handle_table_array(lexer, original, doc) do
    # Guaranteed to have two open brackets
    with {:ok, {?\[, _, _, _}} <- pop_skip(lexer, [:whitespace]),
         {:ok, {?\[, _, _, _}} <- pop_skip(lexer, [:whitespace]),
         {:ok, key, _, _} <- key(lexer),
         {_, {:ok, {?\], _, _, _}}} <- {:close, pop_skip(lexer, [:whitespace])},
         {_, {:ok, {?\], _, _, _}}} <- {:close, pop_skip(lexer, [:whitespace])},
         {:ok, doc} <- Builder.push_table_array(doc, key) do
      # Make sure table opening is followed by newline
      case peek_skip(lexer, [:whitespace]) do
        {:error, _, _, _} = err ->
          err
        {:ok, {:comment, _, _, _}} ->
          do_decode(lexer, original, doc)
        {:ok, {type, _, _, _}} when type in [:newline, :eof] ->
          do_decode(lexer, original, doc)
        {:ok, {type, skip, data, lines}} ->
          {:error, {:expected, :newline, {type, data}}, skip, lines}
      end
    else
      {:error, _, _, _} = err ->
        err
      {_, {:error, _, _, _} = err} ->
        err
      {:close, {:ok, {type, skip, data, lines}}} ->
        {:error, {:unclosed_table_array_name, {type, data}}, skip, lines}
    end
  end
  
  defp maybe_integer(lexer) do
    case pop_skip(lexer, [:whitespace]) do
      {:ok, {type, _skip, _data, _lines}} when type in '-+' ->
        # Can be integer, float
        case Lexer.peek(lexer) do
          {:error, _, _, _} = err ->
            err
          {:ok, {:digits, _, d, _}} ->
            # Appears to be integer or float, continue by accumulating
            Lexer.advance(lexer)
            maybe_integer(lexer, [d, type])
          {:ok, {type, skip, data, lines}} ->
            {:error, {:invalid_token, {type, data}}, skip, lines}
        end
      {:ok, {:digits, skip, <<leader::utf8,_::utf8,_::utf8,_::utf8>> = d, lines} = token} ->
        # Could be a datetime
        case Lexer.peek(lexer) do
          {:ok, {?-, _, _, _}} ->
            # This is a date or datetime
            Lexer.push(lexer, token)
            maybe_datetime(lexer)
          {:ok, {?., _, _, _}} ->
            # Float
            Lexer.advance(lexer)
            float(lexer, ?., [?., d])
          {:ok, {:alpha, <<c::utf8>>}, _, _} when c in 'eE' ->
            # Float
            Lexer.advance(lexer)
            float(lexer, ?e, [?e, ?0, ?., d])
          {:ok, {?_, _, _, _}} ->
            # Integer
            maybe_integer(lexer, [d])
          _ ->
            # Just an integer
            if leader == ?0 do
              # Leading zeroes not allowed
              {:error, {:invalid_integer, :leading_zero}, skip, lines}
            else
              {:ok, String.to_integer(d)}
            end
        end
      {:ok, {:digits, skip, <<leader::utf8,_::utf8>> = d, lines} = token} ->
        # Could be a time
        case Lexer.peek(lexer) do
          {:ok, {?:, _, _, _}} ->
            # This is a local time
            Lexer.push(lexer, token)
            time(lexer)
          _ ->
            # It's just an integer
            if leader == ?0 do
              # Leading zeros not allowed
              {:error, {:invalid_integer, :leading_zero}, skip, lines}
            else
              {:ok, String.to_integer(d)}
            end
        end
      {:ok, {:digits, _, d, _}} ->
        # Just a integer or float
        maybe_integer(lexer, [d])
      {:ok, {type, skip, data, lines}} ->
        {:error, {:invalid_token, {type, data}}, skip, lines}
    end
  end
  
  defp maybe_integer(lexer, parts) do
    case Lexer.pop(lexer) do
      {:error, _, skip, lines} ->
        # Integer
        with {:ok, _} = result <- iodata_to_integer(parts) do
          result
        else
          {:error, reason} ->
            {:error, reason, skip, lines}
        end
      {:ok, {?., _, _, _}} ->
        # Float
        float(lexer, ?., [?. | parts])
      {:ok, {:alpha, _, <<c::utf8>>, _}} when c in 'eE' ->
        # Float, need to add .0 before e, or String.to_float fails
        float(lexer, ?e, [?e, ?0, ?. | parts])
      {:ok, {?_, _, _, _}} ->
        case Lexer.peek(lexer) do
          {:ok, {:digits, _, d, _}} ->
            # Allowed, just skip the underscore
            Lexer.advance(lexer)
            maybe_integer(lexer, [d | parts])
          {:ok, {type, skip, data, lines}} ->
            {:error, {:invalid_token, {type, data}}, skip, lines}
          {:error, _, _, _} = err ->
            err
        end
      {:ok, {_, skip, _, lines} = token} ->
        # Just an integer
        Lexer.push(lexer, token)
        with {:ok, _} = result <- iodata_to_integer(parts) do
          result
        else
          {:error, reason} ->
            {:error, reason, skip, lines}
        end
    end
  end
  
  defp float(lexer, signal, [last | _] = parts) do
    case Lexer.pop(lexer) do
      {:error, _, _, _} = err ->
        err
      {:ok, {?., skip, _, lines}} ->
        # Always an error at this point, as either duplicate or after E
        {:error, {:invalid_float, {?., 0}}, skip, lines}
      {:ok, {sign, _, _, _}} when sign in '-+' and last == ?e ->
        # +/- are allowed after e/E
        float(lexer, signal, [sign | parts])
      {:ok, {:alpha, _, <<c::utf8>>, _}} when c in 'eE' and signal == ?. ->
        # Valid if after a dot
        float(lexer, ?e, [?e | parts])
      {:ok, {?_, skip, _, lines}} when last not in '_e.' ->
        # Valid only when surrounded by digits
        with {:ok, {:digits, _, d, _}} <- Lexer.peek(lexer),
             _ = Lexer.advance(lexer) do
          float(lexer, signal, [d | parts])
        else
          {:error, _, _, _} = err ->
            err
          {:ok, {_, _, _, _}} ->
            {:error, {:invalid_float, {?_, 0}}, skip, lines}
        end
      {:ok, {:digits, _, d, _}} ->
        float(lexer, signal, [d | parts])
      {:ok, {type, skip, data, lines}} when last in 'e.' ->
        # Incomplete float
        {:error, {:invalid_float, {type, data}}, skip, lines}
      {:ok, {_type, skip, _data, lines} = token} when last not in '_e.' ->
        # Done
        Lexer.push(lexer, token)
        with {:ok, _} = result <- iodata_to_float(parts) do
          result
        else
          {:error, reason} ->
            {:error, reason, skip, lines}
        end
      {:ok, {type, skip, data, lines}} ->
        {:error, {:invalid_token, {type, data}}, skip, lines}
    end
  end
  
  defp time(lexer) do
    # At this point we know we have at least HH:
    with {:ok, {:digits, skip, <<_::utf8, _::utf8>> = hh, lines}} <- Lexer.pop(lexer),
         {:ok, {?:, _, _, _}} <- Lexer.pop(lexer),
         {:ok, {:digits, _, <<_::utf8, _::utf8>> = mm, _}} <- Lexer.pop(lexer),
         {:ok, {?:, _, _, _}} <- Lexer.pop(lexer),
         {:ok, {:digits, _, <<_::utf8, _::utf8>> = ss, _}} <- Lexer.pop(lexer) do
      # Check for fractional
      parts = [ss, ?:, mm, ?:, hh]
      parts =
        case Lexer.peek(lexer) do
          {:ok, {?., _, _, _}} ->
            Lexer.advance(lexer)
            case Lexer.pop(lexer) do
              {:ok, {:digits, _, d, _}} ->
                [d, ?. | parts]
              {:ok, {type, skip, data, lines}} ->
                # Invalid
                throw {:error, {:invalid_token, {type, data}}, skip, lines}
              {:error, reason, skip, lines} ->
                throw {:error, {:invalid_fractional_seconds, reason}, skip, lines}
            end
          {:ok, _} ->
            parts
        end
      case Time.from_iso8601(iodata_to_str(parts)) do
        {:ok, _} = result ->
          result
        {:error, :invalid_time} ->
          {:error, :invalid_time, skip, lines}
        {:error, reason} ->
          {:error, {:invalid_time, reason}, skip, lines}
      end
    else
      {:error, _, _, _} = err ->
        err
      {:ok, {type, skip, data, lines}} ->
        {:error, {:invalid_token, {type, data}}, skip, lines}
    end
  catch
    :throw, {:error, _, _, _} = err ->
      err
  end
  
  defp maybe_datetime(lexer) do
    # At this point we have at least YYYY-
    with {:ok, {:digits, _, <<_::utf8,_::utf8,_::utf8,_::utf8>> = yy, _}} <- Lexer.pop(lexer),
         {:ok, {?-, _, _, _}} <- Lexer.pop(lexer),
         {:ok, {:digits, _, <<_::utf8,_::utf8>> = mm, _}} <- Lexer.pop(lexer),
         {:ok, {?-, _, _, _}} <- Lexer.pop(lexer),
         {:ok, {:digits, skip, <<_::utf8, _::utf8>> = dd, lines}} <- Lexer.pop(lexer) do
      # At this point we have a full date, check for time
      case Lexer.pop(lexer) do
        {:ok, {:alpha, _, "T", _}} ->
          # Expecting a time
          with {:ok, time} <- time(lexer) do
            datetime(lexer, [dd, ?-, mm, ?-, yy], time)
          end
        {:ok, {:whitespace, _, _, _}} ->
          case Lexer.peek(lexer) do
            {:ok, {:digits, _, <<_::utf8, _::utf8>>, _}} ->
              # Expecting a time
              with {:ok, time} <- time(lexer) do
                datetime(lexer, [dd, ?-, mm, ?-, yy], time)
              end
            _ ->
              # Just a date
              case Date.from_iso8601(iodata_to_str([dd, ?-, mm, ?-, yy])) do
                {:ok, _} = result ->
                  result
                {:error, :invalid_date} ->
                  {:error, :invalid_date, skip, lines}
                {:error, reason} ->
                  {:error, {:invalid_date, reason}, skip, lines}
              end
          end
        {:ok, {_type, skip, _data, lines} = token} ->
          # Just a date
          Lexer.push(lexer, token)
          case Date.from_iso8601(iodata_to_str([dd, ?-, mm, ?-, yy])) do
            {:ok, _} = result ->
              result
            {:error, :invalid_date} ->
              {:error, :invalid_date, skip, lines}
            {:error, reason} ->
              {:error, {:invalid_date, reason}, skip, lines}
          end
      end
    else
      {:error, _, _, _} = err ->
        err
      {:ok, {type, skip, data, lines}} ->
        {:error, {:invalid_token, {type, data}}, skip, lines}
    end
  end
  
  defp datetime(lexer, parts, time) do
    # At this point we have at least YYYY-mm-dd and a fully decoded time
    with {:ok, date} <- Date.from_iso8601(iodata_to_str(parts)),
         {:ok, naive} <- NaiveDateTime.new(date, time) do
      # We just need to check for Z or UTC offset
      case Lexer.pop(lexer) do
        {:ok, {:alpha, skip, "Z", lines}} ->
          case DateTime.from_naive(naive, "Etc/UTC") do
            {:error, reason} ->
              {:error, {:invalid_datetime, reason}, skip, lines}
            {:ok, _} = result ->
              result
          end
        {:ok, {sign, skip, _, lines}} when sign in '-+' ->
          # We have an offset
          with {:ok, {:digits, _, <<_::utf8,_::utf8>> = hh, _}} <- Lexer.pop(lexer),
              {:ok, {?:, _, _, _}} <- Lexer.pop(lexer),
              {:ok, {:digits, _, <<_::utf8,_::utf8>> = mm, _}} <- Lexer.pop(lexer) do
            # Shift naive to account for offset
            hours = String.to_integer(hh)
            mins = String.to_integer(mm)
            offset = (hours * 60 * 60) + (mins * 60)
            naive =
              case sign do
                ?- ->
                  NaiveDateTime.add(naive, offset * -1, :second)
                ?+ ->
                  NaiveDateTime.add(naive, offset, :second)
              end
            case DateTime.from_naive(naive, "Etc/UTC") do
              {:error, reason} ->
                {:error, {:invalid_datetime, reason}, skip, lines}
              {:ok, _} = result ->
                result
            end
          else
            {:error, _, _, _} = err ->
              err
            {:ok, {type, skip, data, lines}} ->
              {:error, {:invalid_datetime_offset, {type, data}}, skip, lines}
          end
        {:ok, {type, _, _, _}} when type in [:eof, :whitespace, :newline] ->
          # Just a local date/time
          {:ok, naive}
      end
    else
      {:error, _, _, _} = err ->
        err
      {:ok, {type, skip, data, lines}} ->
        {:error, {:invalid_token, {type, data}}, skip, lines}
    end
  end
  
  # Allowed values
  # - Array
  # - Inline table
  # - Integer (in all forms)
  # - Float
  # - String
  # - DateTime
  defp value(lexer) do
    case peek_skip(lexer, [:whitespace]) do
      {:error, _, _, _} = err ->
        err
      {:ok, {:comment, _, _, _}} ->
        Lexer.advance(lexer)
        value(lexer)
      {:ok, {?\[, skip, _, lines}} ->
        # Need to embellish some errors with line/col
        with {:ok, _} = ok <- array(lexer) do
          ok
        else
          {:error, _, _, _} = err ->
            err
          {:error, {:invalid_array, _} = reason} ->
            {:error, reason, skip, lines}
        end
      {:ok, {?\{, _, _, _}} ->
        inline_table(lexer)
      {:ok, {:hex, _, v, _}} ->
        Lexer.advance(lexer)
        {:ok, String.to_integer(v, 16)}
      {:ok, {:octal, _, v, _}} ->
        Lexer.advance(lexer)
        {:ok, String.to_integer(v, 8)}
      {:ok, {:binary, _, v, _}} ->
        Lexer.advance(lexer)
        {:ok, String.to_integer(v, 2)}
      {:ok, {true, _, _, _}} ->
        Lexer.advance(lexer)
        {:ok, true}
      {:ok, {false, _, _, _}} ->
        Lexer.advance(lexer)
        {:ok, false}
      {:ok, {type, _, v, _}} when type in [:string, :multiline_string] ->
        Lexer.advance(lexer)
        {:ok, v}
      {:ok, {sign, _, _, _}} when sign in '-+' ->
        maybe_integer(lexer)
      {:ok, {:digits, skip, <<?0, rest::binary>>, lines}} when byte_size(rest) > 0 ->
        {:error, {:invalid_integer, :leading_zero}, skip, lines}
      {:ok, {:digits, _, _, _}} ->
        maybe_integer(lexer)
      {:ok, {type, skip, data, lines}} ->
        {:error, {:invalid_token, {type, data}}, skip, lines}
    end
  end
  
  defp array(lexer) do
    with {:ok, {?\[, skip, _, lines}} <- pop_skip(lexer, [:whitespace]),
         {:ok, elements} <- accumulate_array_elements(lexer),
         {:valid?, true} <- {:valid?, valid_array?(elements)},
         {_, _, {:ok, {?\], _, _, _}}} <- {:close, {skip, lines}, pop_skip(lexer, [:whitespace, :newline, :comment])} do
      {:ok, elements}
    else
      {:error, _, _, _} = err ->
        err
      {:close, {:error, _, _, _} = err} ->
        err
      {:close, {_oline, _ocol} = opened, {:ok, {_, eskip, _, elines}}} ->
        {:error, {:unclosed_array, opened}, eskip, elines}
      {:valid?, err} ->
        err
    end
  end
  
  defp valid_array?([]), 
    do: true
  defp valid_array?([h | t]), 
    do: valid_array?(t, typeof(h))
  defp valid_array?([], _type), 
    do: true
  defp valid_array?([h | t], type) do
    if typeof(h) == type do
      valid_array?(t, type)
    else
      {:error, {:invalid_array, {:expected_type, t, h}}}
    end
  end
  
  defp typeof(v) when is_integer(v), do: :integer
  defp typeof(v) when is_float(v), do: :float
  defp typeof(v) when is_binary(v), do: :string
  defp typeof(%Time{}), do: :time
  defp typeof(%Date{}), do: :date
  defp typeof(%DateTime{}), do: :datetime
  defp typeof(%NaiveDateTime{}), do: :datetime
  defp typeof(v) when is_list(v), do: :list
  defp typeof(v) when is_map(v), do: :map
  
  defp inline_table(lexer) do
    with {:ok, {?\{, skip, _, lines}} <- pop_skip(lexer, [:whitespace]),
         {:ok, elements} <- accumulate_table_elements(lexer),
         {_, _, {:ok, {?\}, _, _, _}}} <- {:close, {skip, lines}, pop_skip(lexer, [:whitespace])} do
      {:ok, elements}
    else
      {:error, _, _, _} = err ->
        err
      {:close, {:error, _, _, _} = err} ->
        err
      {:close, {_oskip, _olines} = opened, {:ok, {_, eskip, _, elines}}} ->
        {:error, {:unclosed_inline_table, opened}, eskip, elines}
    end   
  end

  
  defp accumulate_array_elements(lexer) do
    accumulate_array_elements(lexer, [])
  end
  defp accumulate_array_elements(lexer, acc) do
    with {:ok, {type, _, _, _}} <- peek_skip(lexer, [:whitespace, :newline, :comment]),
         {_, false} <- {:trailing_comma, type == ?\]},
         {:ok, value} <- value(lexer),
         {:ok, {next, _, _, _}} <- peek_skip(lexer, [:whitespace]) do
      if next == ?, do
        Lexer.advance(lexer)
        accumulate_array_elements(lexer, [value | acc])
      else
        {:ok, [value | acc]}
      end
    else
      {:error, _, _, _} = err ->
        err
      {:trailing_comma, true} ->
        {:ok, acc}
    end
  end
  
  defp accumulate_table_elements(lexer) do
    accumulate_table_elements(lexer, %{})
  end
  defp accumulate_table_elements(lexer, acc) do
    with {:ok, {type, _, _, _}} <- peek_skip(lexer, [:whitespace, :newline, :comment]),
         {_, false} <- {:trailing_comma, type == ?\}},
         {:ok, key, skip, lines} <- key(lexer),
         {_, _, false, _, _} <- {:key_exists, key, Map.has_key?(acc, key), skip, lines},
         {:ok, {?=, _, _, _}} <- pop_skip(lexer, [:whitespace, :comments]),
         {:ok, value} <- value(lexer),
         {_, {:ok, acc2}} <- {key, Builder.push_key_into_table(acc, key, value)},
         {:ok, {next, _, _, _}} <- peek_skip(lexer, [:whitespace, :comments]) do
      if next == ?, do
        Lexer.advance(lexer)
        accumulate_table_elements(lexer, acc2)
      else
        {:ok, acc2}
      end
    else
      {:error, _, _, _} = err ->
        err
      {:key_exists, key, true, line, col} ->
        {:error, {:key_exists, key}, line, col}
      {table, {:error, :key_exists}} ->
        {:error, {:key_exists_in_table, table}, -1, -1}
      {:trailing_comma, true} ->
        {:ok, acc}
      {:ok, {type, skip, data, lines} = token} ->
        Lexer.push(lexer, token)
        {:error, {:invalid_key_value, {type, data}}, skip, lines}
    end
  end
  
  defp key(lexer) do
    result =
      case pop_skip(lexer, [:whitespace]) do
        {:error, _, _, _} = err ->
          err
        {:ok, {type, skip, s, lines}} when type in [:digits, :alpha, :string] ->
          {key(lexer, s, []), skip, lines}
        {:ok, {type, skip, _, lines}} when type in '-_' ->
          {key(lexer, <<type::utf8>>, []), skip, lines}
        {:ok, {type, skip, data, lines} = token} ->
          Lexer.push(lexer, token)
          {:error, {:invalid_token, {type, data}}, skip, lines}
      end
    case result do
      {:error, _, _, _} = err ->
        err
      {{:ok, key}, skip, lines} ->
        {:ok, key, skip, lines}
      {{:error, _, _, _} = err, _, _} ->
        err
    end
  end
  defp key(lexer, word, acc) do
    case Lexer.peek(lexer) do
      {:error, _, _, _} = err ->
        err
      {:ok, {type, _, s, _}} when type in [:digits, :alpha, :string] ->
        Lexer.advance(lexer)
        key(lexer, word <> s, acc)
      {:ok, {type, _, _, _}} when type in '-_' ->
        Lexer.advance(lexer)
        key(lexer, word <> iodata_to_str([type]), acc)
      {:ok, {?., _, _, _}} ->
        Lexer.advance(lexer)
        case Lexer.peek(lexer) do
          {:error, _, _, _} = err ->
            err
          {:ok, {type, _, _, _}} when type in [:digits, :alpha, :string] ->
            key(lexer, "", [word | acc])
          {:ok, {type, _, _, _}} when type in '-_' ->
            key(lexer, "", [word | acc])
          {:ok, {type, skip, data, lines}} ->
            {:error, {:invalid_token, {type, data}}, skip, lines}
        end
      {:ok, _} ->
        {:ok, Enum.reverse([word | acc])}
    end
  end
  
  defp iodata_to_integer(data) do
    case iodata_to_str(data) do
      <<?0, rest::binary>> when byte_size(rest) > 0 ->
        {:error, {:invalid_integer, :leading_zero}}
      <<sign::utf8, ?0, rest::binary>> when (sign == ?- or sign == ?+) and byte_size(rest) > 0 ->
        {:error, {:invalid_integer, :leading_zero}}
      s ->
        {:ok, String.to_integer(s)}
    end
  end
  
  defp iodata_to_float(data) do
    case iodata_to_str(data) do
      <<?0, next::utf8, _::binary>> when next != ?. ->
        {:error, {:invalid_float, :leading_zero}}
      <<sign::utf8, ?0, next::utf8, _::binary>> when (sign == ?- or sign == ?+) and next != ?. ->
        {:error, {:invalid_float, :leading_zero}}
      s ->
        {:ok, String.to_float(s)}
    end
  end
  
  defp iodata_to_str(parts) do
    parts
    |> Enum.reverse
    |> IO.iodata_to_binary()
  end
  
  defp pop_skip(lexer, skip) do
    case Lexer.pop(lexer) do
      {:error, _, _, _} = err ->
        err
      {:ok, {type, _, _, _}} = result ->
        if :lists.member(type, skip) do
          pop_skip(lexer, skip)
        else
          result
        end
    end
  end
  
  defp peek_skip(lexer, skip) do
    case Lexer.peek(lexer) do
      {:error, _, _, _} = err ->
        err
      {:ok, {type, _, _, _}} = result ->
        if :lists.member(type, skip) do
          Lexer.advance(lexer)
          peek_skip(lexer, skip)
        else
          result
        end
    end
  end
end
