decode_jobs = %{
  "toml"  => fn path -> {:ok, _} = Toml.decode_file(path) end,
  # Incorrect implementation of 0.5.0 (expected, but fails during parsing)
  # "toml_elixir" => fn path -> {:ok, _} = TomlElixir.parse_file(path) end,
  # Doesn't support 0.5.0 spec, or incomplete
  # "tomlex"    => fn path -> %{} = Tomlex.load(File.read!(path)) end,
  # "jerry"   => fn path -> %{} = Jerry.decode(File.read!(path)) end,
  # "etoml"  => fn path -> {:ok, _} = :etoml.parse(File.read!(path)) end,
}

inputs = %{
  "example.toml" => Path.join([__DIR__, "..", "test", "fixtures", "example.toml"])
}

Benchee.run(decode_jobs,
  warmup: 5,
  time: 30,
  memory_time: 1,
  inputs: inputs,
  formatters: [
    {Benchee.Formatters.HTML, file: Path.expand("output/decode.html", __DIR__)},
    Benchee.Formatters.Console
  ]
)
