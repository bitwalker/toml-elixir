defmodule Toml.Error do
  @moduledoc false
  
  defexception [:message, :reason]
  
  def exception({:error, {:invalid_toml, reason}}) when is_binary(reason) do
    %__MODULE__{message: reason, reason: nil}
  end
  def exception(msg) when is_binary(msg) do
    %__MODULE__{message: msg, reason: nil}
  end
  def exception({:error, reason}) do
    %__MODULE__{message: format_reason(reason), reason: reason}
  end
  
  @doc """
  Convert internal error reasons into friendly, printable form
  """
  def format_reason({:keys, {:non_existing_atom, key}}),
    do: "unable to convert '#{key}' to an existing atom"
  def format_reason({:expected, token, other}),
    do: "expected #{format_token(token)}, but got #{format_token(other)}"
  def format_reason({:invalid_token, token}),
    do: "invalid token #{format_token(token)}"
  def format_reason({:invalid_integer, :leading_zero}),
    do: "invalid integer syntax, leading zeros are not allowed"
  def format_reason({:invalid_float, :leading_zero}),
    do: "invalid float syntax, leading zeros are not allowed"
  def format_reason({:invalid_float, token}),
    do: "invalid float syntax, unexpected token #{format_token(token)}"
  def format_reason({:invalid_datetime, reason}),
    do: "invalid datetime syntax, #{inspect reason}"
  def format_reason({:invalid_datetime_offset, reason}),
    do: "invalid datetime offset syntax, #{inspect reason}"
  def format_reason({:invalid_date, reason}),
    do: "invalid date syntax, #{inspect reason}"
  def format_reason({:invalid_time, reason}),
    do: "invalid time syntax, #{inspect reason}"
  def format_reason({:invalid_key_value, token}),
    do: "invalid key/value syntax, unexpected token #{format_token(token)}"
  def format_reason({:unclosed_table_array_name, token}),
    do: "unclosed table array name at #{format_token(token)}"
  def format_reason({:unclosed_array, {oline, ocol}}),
    do: "unclosed array started at #{oline}:#{ocol}"
  def format_reason({:unclosed_inline_table, {oline, ocol}}),
    do: "unclosed inline table started at #{oline}:#{ocol}"
  def format_reason(:unclosed_quote),
    do: "unclosed quoted string"
  def format_reason(:unexpected_newline),
    do: "unexpected newline in single-quoted string"
  def format_reason(:unexpected_eof),
    do: "unexpected end of file"
  def format_reason({:invalid_escape, char}),
    do: "illegal escape sequence #{char}"
  def format_reason({:invalid_char, char}) do
    if String.printable?(char) do
      "illegal character #{inspect char, base: :hex} ('#{char}')"
    else
      "illegal character #{inspect char, base: :hex}"
    end
  end
  def format_reason({:invalid_unicode, message}) do
    "illegal unicode escape, #{message}"
  end
  def format_reason({:key_exists, key}) do
    "cannot redefine key '#{key}'"
  end
  def format_reason(reason), do: "#{inspect reason}"
  
  # Format a token in `{type, data}`, or `type` form into printable representation
  defp format_token({true, _}), do: "'true'"
  defp format_token({false, _}), do: "'false'"
  defp format_token(:newline), do: "'\\n'"
  defp format_token({_, data}) when is_binary(data),
    do: "'#{data}'"
  defp format_token({token, data}) when is_atom(token),
    do: "'#{data}' (#{token})"
  defp format_token({token, _}),
    do: "'#{<<token>>}'"
  defp format_token(token),
    do: "'#{<<token>>}'"
end
