defmodule Toml.Error do
  @moduledoc false
  
  defexception [:message]
  
  def exception({:error, {:invalid_toml, reason}}) when is_binary(reason) do
    %__MODULE__{message: "Invalid TOML: #{reason}"}
  end
  def exception(msg) when is_binary(msg) do
    %__MODULE__{message: msg}
  end
end
