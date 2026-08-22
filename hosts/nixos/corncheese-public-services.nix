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
    icloud-mail-mcp = {
      endpoint = endpointFor "icloud-mail-mcp" 8781;
      route = {
        host = "mail.corncheese.org";
        auth.mode = "public";
        rateLimit = {
          average = 60;
          burst = 30;
        };
      };
      oidcClient = {
        clientId = "chatgpt-icloud-mail";
        clientName = "ChatGPT iCloud Mail MCP";
        public = true;
        authorizationPolicy = "two_factor";
        requirePkce = true;
        pkceChallengeMethod = "S256";
        redirectUris = [ "https://chatgpt.com/connector_platform_oauth_redirect" ];
        audience = [ "https://mail.corncheese.org/mcp" ];
        scopes = [
          "openid"
          "profile"
          "email"
          "offline_access"
          "mail.read"
        ];
        grantTypes = [
          "authorization_code"
          "refresh_token"
        ];
        responseTypes = [ "code" ];
        accessTokenSignedResponseAlg = "RS256";
        userinfoSignedResponseAlg = "none";
        tokenEndpointAuthMethod = "none";
        consentMode = "explicit";
      };
    };
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

  corncheese-server.auth.authelia.oidcScopes."mail.read".claims = [ ];
}
