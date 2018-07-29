defmodule Reader do
  def read(%Toml.Lexer{} = lexer) do
    case Toml.Lexer.pop(lexer) do
      {:ok, {:eof, _, _, _}} ->
        :ok
      {:error, _, _, _} = err ->
        throw err
      {:ok, _token} ->
        read(lexer)
    end
  end
  
  def read_stream(%Toml.Lexer{} = lexer) do
    lexer 
    |> Toml.Lexer.stream() 
    |> Stream.map(fn  
      {:error, _, _, _} = err ->
        throw err
      {:ok, _} = ok ->
        ok
    end)
    |> Stream.run
  end
end
