defmodule Toml.Test.TransformTest do
  use ExUnit.Case

  defmodule Server do
    defstruct [:name, :ip, :ports]
  end

  defmodule PortsToList do
    def transform(:ports, v) when is_list(v) do
      v |> Enum.map(fn port -> port[:number] end)
    end

    def transform(_k, v), do: v
  end

  defmodule IPStringToCharlistTransform do
    def transform(:ip, v) when is_binary(v) do
      String.to_charlist(v)
    end

    def transform(_k, v), do: v
  end

  defmodule IPAddressTransform do
    def transform(:ip, v) when is_list(v) do
      case :inet.parse_ipv4_address(v) do
        {:ok, ip} ->
          ip

        {:error, reason} ->
          {:error, {:invalid_ip, {v, reason}}}
      end
    end

    def transform(:ip, v), do: {:error, {:invalid_ip, v}}
    def transform(_k, v), do: v
  end

  defmodule ServerTransform do
    def transform(:servers, v) when is_map(v) do
      for {name, s} <- Enum.sort(v) do
        case s do
          %{ip: {_, _, _, _}} ->
            struct(Toml.Test.TransformTest.Server, Map.put(s, :name, name))

          _ ->
            {:error, {:invalid_servers, :ip_address_not_parsed_yet}}
        end
      end
    end

    def transform(:servers, v), do: {:error, {:invalid_servers, v}}
    def transform(_k, v), do: v
  end

  test "transforms are applied in order, and depth-first, bottom-up" do
    # This test is designed to fail if the transforms are executed out of order,
    # if transforms are not executed bottom up, the order should be as follows:
    #   - ip is converted to charlist
    #   - ip is converted to ip tuple
    #   - server struct is built from server table
    #   - list of servers is generated from servers table
    input = """
    [servers.alpha]
    ip = "192.168.1.1"

    [[servers.alpha.ports]]
    type = "UDP"
    number = 8080
    [[servers.alpha.ports]]
    type = "UDP"
    number = 8081

    [servers.beta]
    ip = "192.168.1.2"

    [[servers.beta.ports]]
    type = "UDP"
    number = 8082
    [[servers.beta.ports]]
    type = "UDP"
    number = 8083

    [servers.gamma]
    ip = "192.168.1.3"
    ports = [
      {type = "TCP", number = 8888},
      {type = "TCP", number = 9000}
    ]
    """

    transforms = [
      PortsToList,
      IPStringToCharlistTransform,
      IPAddressTransform,
      ServerTransform
    ]

    assert {:ok, result} = Toml.decode(input, keys: :atoms, transforms: transforms)
    assert is_list(result[:servers])
    assert [%Server{name: :alpha, ip: {192, 168, 1, 1}} | _] = result[:servers]
    [alpha, _beta, gamma] = result[:servers]
    assert [8080, 8081] = alpha.ports
    assert [8888, 9000] = gamma.ports
  end
end
