defmodule Toml.Test.ProviderTest do
  use ExUnit.Case

  test "can initialize provider from sample toml" do
    file = Path.join([__DIR__, "fixtures", "provider.toml"])
    opts = Toml.Provider.init(path: file)
    config = Toml.Provider.load([], opts)
    assert "success!" = Keyword.get(config, :toml, :provider_test)
    Application.put_all_env(config)
    assert {:ok, "success!"} = Toml.Provider.get([:toml, :provider_test])

    assert true == Application.get_env(:toml, :provider_active)
    assert {:ok, true} = Toml.Provider.get([:toml, :provider_active])

    assert false == Application.get_env(:toml, :provider_disabled)
    assert {:ok, false} = Toml.Provider.get([:toml, :provider_disabled])

    Application.put_env(:toml, :provider_test, nil)
    assert nil == Application.get_env(:toml, :provider_test)

    opts = Toml.Provider.init(path: file, keys: :atoms!)
    config = Toml.Provider.load(config, opts)
    Application.put_all_env(config)
    assert "success!" = Application.get_env(:toml, :provider_test)
    assert {:ok, "success!"} = Toml.Provider.get([:toml, :provider_test])

    Application.put_env(:toml, :provider_test, :preexisting)
    Application.put_env(:toml, :nested, foo: "baz")
    assert :preexisting == Application.get_env(:toml, :provider_test)

    opts = Toml.Provider.init(path: file)
    config = Toml.Provider.load(config, opts)
    assert "success!" = Application.get_env(:toml, :provider_test)
    assert {:ok, "success!"} = Toml.Provider.get([:toml, :provider_test])
  end

  test "exit is triggered if path provided has invalid expansion" do
    assert catch_exit(Toml.Provider.init(path: "path/to/${HOME")) == :unclosed_var_expansion
  end

  test "can expand paths" do
    home = Path.join("/path/to/", System.get_env("HOME"))
    assert {:ok, ^home} = Toml.Provider.expand_path("/path/to/${HOME}")
  end

  test "friendly error if bad expansion provided" do
    assert {:error, _} = Toml.Provider.expand_path("/path/to/${HOME")
  end
end
