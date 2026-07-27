{ config, ... }:
let
  topology = config.corncheese-server._meta.topology;
  wotboxPath = "/media/music/wotbox";
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
    wotbox = {
      endpoint = endpointFor "wotbox" 8780;
      route = {
        host = "home.conroycheers.me";
        path = wotboxPath;
        stripPrefix = [ wotboxPath ];
        auth.mode = "forwardAuth";
        auth.policy = "one_factor";
      };
      homepage = {
        section = "Media";
        order = 110;
        name = "Wotbox";
        route = "wotbox";
        icon = "mdi-music-box-multiple";
        description = "Music tracker search and downloads";
      };
    };
  };
}
