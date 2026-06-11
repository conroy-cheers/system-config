{ config, ... }:
let
  topology = config.corncheese-server._meta.topology;
  endpointFor = service: port: {
    scheme = "http";
    inherit port;
    bindAddress = topology.serviceListenAddress service "127.0.0.1";
  };
in
{
  corncheese-server._meta.services = {
    ultramoji = {
      endpoint = endpointFor "ultramoji" 8765;
      route = {
        host = "ultramoji.corncheese.org";
        auth.mode = "public";
        backend.url = "http://127.0.0.1:8765";
      };
    };
  };
}
