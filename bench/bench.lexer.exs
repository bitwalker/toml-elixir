jobs = %{
  "recursive read" => fn content -> 
    {:ok, lexer} = Toml.Lexer.new(content)
    :ok = Reader.read(lexer)
  end,
  "stream read" => fn content -> 
    {:ok, lexer} = Toml.Lexer.new(content)
    :ok = Reader.read_stream(lexer)
  end
}

inputs = %{
  "example.toml" => File.read!(Path.join([__DIR__, "..", "test", "fixtures", "example.toml"]))
}

Benchee.run(jobs,
  warmup: 5,
  time: 30,
  memory_time: 1,
  inputs: inputs,
  formatters: [
    {Benchee.Formatters.HTML, file: Path.expand("output/lexer.html", __DIR__)},
    Benchee.Formatters.Console,
  ]
)
