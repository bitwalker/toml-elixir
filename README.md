# TOML for Elixir

[![Master](https://travis-ci.com/bitwalker/toml-elixir.svg?branch=master)](https://travis-ci.org/bitwalker/toml-elixir)
[![Hex.pm Version](http://img.shields.io/hexpm/v/toml-elixir.svg?style=flat)](https://hex.pm/packages/toml-elixir)

This is a TOML library for Elixir projects. It is compliant with version 0.5.0 of the
[official TOML specification](https://github.com/toml-lang/toml). You can find a
brief overview of the feature set below, but you are encouraged to read the full
spec at the link above (it is short and easy to read!).

## Features

- Parse from string, file, or stream
- Fully compliant with the latest version of the TOML spec
- Is tested against [toml-test](https://github.com/BurntSushi/toml-test), a test
  suite for spec-compliant TOML encoders/decoders, used by implementations in
  multiple languages. The test suite has been integrated into this project to be
  run under Mix so that we get better error information and so it can run as
  part of the test suite.
- Parser produces a map with values using the appropriate Elixir data types for
  representation
- Supports use as a configuration provider in Distillery 2.x+ (use TOML
  files for configuration!)
- Parser is written by hand to take advantage of various optimizations.

## Installation

This library is available on Hex as `:toml`, and can be added to your deps like so:

```elixir
def deps do
  [
    {:toml, "~> 0.1.0"}
  ]
end
```

## Type Conversions

In case you are curious how TOML types are translated to Elixir types, the
following table provides the conversions.

**NOTE:** The various possible representations of each type, such as
hex/octal/binary integers, quoted/literal strings, etc., are considered to be
the same base type (e.g. integer and string respectively in the examples given).

| TOML | Elixir |
|-------|-------|
| String | String.t (binary) |
| Integer | integer |
| Boolean | boolean |
| Offset Date-Time | DateTime.t |
| Local Date-Time | NaiveDateTime.t |
| Local Date | Date.t |
| Local Time | Time.t |
| Array | list |
| Table | map |
| Table Array | list(map) |

## Example Usage

The following is a brief overview of how to use this library. First, let's take
a look at an example TOML file, as borrowed from the [TOML
homepage](https://github.com/toml-lang/toml):

``` toml
# This is a TOML document.

title = "TOML Example"

[owner]
name = "Tom Preston-Werner"
dob = 1979-05-27T07:32:00-08:00 # First class dates

[database]
server = "192.168.1.1"
ports = [ 8001, 8001, 8002 ]
connection_max = 5000
enabled = true

[servers]

  # Indentation (tabs and/or spaces) is allowed but not required
  [servers.alpha]
  ip = "10.0.0.1"
  dc = "eqdc10"

  [servers.beta]
  ip = "10.0.0.2"
  dc = "eqdc10"

[clients]
data = [ ["gamma", "delta"], [1, 2] ]

# Line breaks are OK when inside arrays
hosts = [
  "alpha",
  "omega"
]
```

### Parsing

```elixir
iex> input = """
[database]
server = "192.168.1.1"
"""
...> {:ok, %{"database" => %{"server" => "192.168.1.1"}}} = Toml.parse(input)
...> stream = File.stream!("example.toml")
...> {:ok, %{"database" => %{"server" => "192.168.1.1"}}} = Toml.parse_stream(stream)
...> {:ok, %{"database" => %{"server" => "192.168.1.1"}}} = Toml.parse_file("example.toml")
...> invalid = """
[invalid]
a = 1 b = 2
"""
...> {:error, {:invalid_toml, reason}} = Toml.parse(invalid); IO.puts(reason)
expected '\n', but got 'b' in nofile on line 2:

    a = 1 b = 2
         ^

:ok
```

## Using with Distillery

To use this library as a configuration provider in Distillery, add the following
to your `rel/config.exs`:

``` elixir
release :myapp do
  # ...snip...
  set config_providers: [{Toml.Provider, ["${XDG_CONFIG_DIR}/myapp.toml"]}]
end
```

This will result in `Toml.Provider` being invoked during boot, at which point it
will evaluate the given path and read the TOML file it finds. If one is not
found, or is not accessible, the provider will raise an error, and the boot
sequence will terminate unsuccessfully. If it succeeds, it persists settings in
the file to the application environment (i.e. you access it via
`Application.get_env/2`).

The config provider expects a certain format to the TOML file, namely that keys
at the root of the document correspond to applications which need to be configured.
If it encounters keys at the root of the document which are not tables, they are ignored.

``` toml
# This is an example of something that would be ignored
title = "My config file"

# We're expecting something like this:
[myapp]
key = value

# To use a bit of Phoenix config, you translate to TOML like so:
[myapp."MyApp.Endpoint"]
cache_static_manifest = "priv/static/cache_manifest.json"

[myapp."MyApp.Endpoint".http]
port = "4000"

[myapp."MyApp.Endpoint".force_ssl]
hsts = true

# Or logger..
[logger]
level = "info"

[logger.console]
format = "[$level] $message \n"
```

## Roadmap

- [ ] Add benchmarking suite
- [ ] Optimize lexer to always send offsets to parser, rather than only in some cases
- [ ] Provide options for converting keys to atom, similar to Jason/Poison/etc.
- [ ] Try to find pathological TOML files to test

## License

This project is licensed Apache 2.0, see the `LICENSE` file in this repo for details.
