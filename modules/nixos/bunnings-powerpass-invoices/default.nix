{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.bunnings-powerpass-invoices;
  serviceName = "bunnings-powerpass-invoices";
  browserServiceName = "${serviceName}-browser";
  serviceUser = serviceName;
  loginUser = "powerpass-login";
  stateRoot = "/var/lib/${cfg.stateDirectory}";
  credentialDirectory = "/var/lib/${cfg.stateDirectory}-credentials";
  credentialName = "${serviceName}-login";
  credentialCache = "${credentialDirectory}/login.cred";
  profile = "${stateRoot}/chromium";
  cdpUrl = "http://127.0.0.1:${toString cfg.browserPort}";

  backend = pkgs.writeShellApplication {
    name = "bunnings-powerpass-invoices-mcp-backend";
    text = ''
      exec ${lib.getExe cfg.package} \
        --profile ${lib.escapeShellArg profile} \
        --cdp-url ${lib.escapeShellArg cdpUrl} \
        --session-only \
        mcp
    '';
  };

  login = pkgs.writeShellApplication {
    name = "bunnings-powerpass-invoices-login";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then
        echo "Run this command with sudo so it can pause the MCP service." >&2
        exit 1
      fi

      systemctl start ${browserServiceName}.service
      systemctl stop ${serviceName}.service

      credential_args=()
      credential_runtime=""

      resume_service() {
        if [[ -n "$credential_runtime" ]]; then
          if [[ -e "$credential_runtime/credentials" ]]; then
            unlink "$credential_runtime/credentials"
          fi
          rmdir "$credential_runtime"
        fi
        systemctl start ${serviceName}.service
      }
      trap resume_service EXIT

      if [[ -f ${lib.escapeShellArg credentialCache} ]]; then
        credential_runtime=$(mktemp -d --tmpdir=/run ${serviceName}-login.XXXXXX)
        chown ${loginUser}:${loginUser} "$credential_runtime"
        chmod 0700 "$credential_runtime"
        systemd-creds decrypt \
          --quiet \
          --refuse-null \
          --name=${lib.escapeShellArg credentialName} \
          ${lib.escapeShellArg credentialCache} \
          - >"$credential_runtime/credentials"
        chown ${loginUser}:${loginUser} "$credential_runtime/credentials"
        chmod 0400 "$credential_runtime/credentials"
        credential_args=(--credentials-file "$credential_runtime/credentials")
      fi

      install -d -m 0700 -o ${serviceUser} -g ${serviceUser} ${lib.escapeShellArg stateRoot}
      install -d -m 0700 -o ${serviceUser} -g ${serviceUser} ${lib.escapeShellArg profile}
      runuser -u ${loginUser} -- \
        env HOME=/var/empty XDG_STATE_HOME=/var/empty \
        ${lib.getExe cfg.package} \
          --profile ${lib.escapeShellArg profile} \
          --cdp-url ${lib.escapeShellArg cdpUrl} \
          "''${credential_args[@]}" \
          login-cli
    '';
  };

  cacheCredentials = pkgs.writeShellApplication {
    name = "bunnings-powerpass-invoices-cache-credentials";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then
        echo "Run this command with sudo so the cache remains root-only." >&2
        exit 1
      fi

      install -d -m 0700 -o root -g root ${lib.escapeShellArg credentialDirectory}

      if [[ "''${1:-}" == "--remove" ]]; then
        if [[ -e ${lib.escapeShellArg credentialCache} ]]; then
          unlink ${lib.escapeShellArg credentialCache}
          echo "Removed the cached PowerPass credentials."
        else
          echo "No cached PowerPass credentials were present."
        fi
        exit 0
      elif [[ $# -ne 0 ]]; then
        echo "Usage: bunnings-powerpass-invoices-cache-credentials [--remove]" >&2
        exit 2
      fi

      if [[ ! -t 0 ]]; then
        echo "Credential entry requires an interactive terminal." >&2
        exit 1
      fi

      IFS= read -r -p "Bunnings username: " username
      IFS= read -r -s -p "Bunnings password: " password
      echo >&2
      if [[ -z "$username" || -z "$password" ]]; then
        echo "Both username and password are required." >&2
        exit 1
      fi

      umask 0077
      encrypted=$(mktemp ${lib.escapeShellArg "${credentialDirectory}/.login.cred.XXXXXX"})
      cleanup() {
        if [[ -e "$encrypted" ]]; then
          unlink "$encrypted"
        fi
      }
      trap cleanup EXIT

      systemd-creds setup
      printf '%s\n%s\n' "$username" "$password" | \
        systemd-creds encrypt \
          --quiet \
          --with-key=host \
          --name=${lib.escapeShellArg credentialName} \
          - \
          - >"$encrypted"
      unset username password
      install -m 0600 -o root -g root "$encrypted" ${lib.escapeShellArg credentialCache}
      echo "Cached the PowerPass credentials using this host's systemd credential key."
    '';
  };

  hardening = {
    CapabilityBoundingSet = "";
    DevicePolicy = "closed";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RemoveIPC = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
in
{
  options.services.bunnings-powerpass-invoices = {
    enable = lib.mkEnableOption "read-only Bunnings PowerPass invoice MCP access";

    package = lib.mkPackageOption pkgs "bunnings-powerpass-invoices" { };
    gatewayPackage = lib.mkPackageOption pkgs "oauth-mcp-gateway" { };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = serviceName;
      description = "Directory below /var/lib containing the trusted Chromium profile.";
    };

    browserPort = lib.mkOption {
      type = lib.types.port;
      default = 9223;
      description = "Loopback Chromium DevTools port shared by the login helper and MCP backend.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which the Streamable HTTP MCP endpoint listens.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8782;
      description = "Port on which the Streamable HTTP MCP endpoint listens.";
    };

    mcpPath = lib.mkOption {
      type = lib.types.str;
      default = "/mcp";
      description = "Public path of the Streamable HTTP MCP endpoint.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      description = "Public HTTPS origin used in OAuth protected-resource metadata.";
    };

    oauth = {
      issuer = lib.mkOption {
        type = lib.types.str;
        description = "OAuth issuer accepted by the MCP resource server.";
      };

      jwksUri = lib.mkOption {
        type = lib.types.str;
        description = "JWKS endpoint used to verify OAuth access tokens.";
      };

      audience = lib.mkOption {
        type = lib.types.str;
        description = "Required access-token audience.";
      };

      requiredScopes = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        default = [ "powerpass.invoices.read" ];
        description = "OAuth scopes required on every MCP request.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl && !lib.hasSuffix "/" cfg.publicUrl;
        message = "services.bunnings-powerpass-invoices.publicUrl must be an HTTPS origin without a trailing slash.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.mcpPath;
        message = "services.bunnings-powerpass-invoices.mcpPath must begin with a slash.";
      }
      {
        assertion = cfg.oauth.audience == "${cfg.publicUrl}${cfg.mcpPath}";
        message = "services.bunnings-powerpass-invoices.oauth.audience must exactly match publicUrl plus mcpPath.";
      }
      {
        assertion = cfg.browserPort != cfg.port;
        message = "services.bunnings-powerpass-invoices.browserPort must differ from the MCP port.";
      }
    ];

    users.users.${serviceUser} = {
      isSystemUser = true;
      group = serviceUser;
      home = stateRoot;
      description = "Read-only Bunnings PowerPass invoice MCP access";
    };
    users.groups.${serviceUser} = { };
    users.users.${loginUser} = {
      isSystemUser = true;
      group = loginUser;
      home = "/var/empty";
      description = "Isolated interactive PowerPass login helper";
    };
    users.groups.${loginUser} = { };

    environment.systemPackages = [
      cacheCredentials
      login
    ];

    systemd.tmpfiles.rules = [
      "d ${credentialDirectory} 0700 root root -"
    ];

    systemd.services.${browserServiceName} = {
      description = "Long-lived Chromium session for Bunnings PowerPass";
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = false;
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      script = ''
        exec ${lib.getExe cfg.package} \
          --profile ${lib.escapeShellArg profile} \
          browser-daemon \
          --listen-address 127.0.0.1 \
          --port ${toString cfg.browserPort}
      '';

      postStart = ''
        for attempt in {1..60}; do
          if ${lib.getExe pkgs.curl} --fail --silent --show-error \
            ${lib.escapeShellArg "${cdpUrl}/json/version"} >/dev/null; then
            exit 0
          fi
          sleep 0.25
        done
        echo "Chromium DevTools endpoint did not become ready" >&2
        exit 1
      '';

      environment = {
        HOME = stateRoot;
        XDG_STATE_HOME = stateRoot;
      };

      serviceConfig = hardening // {
        User = serviceUser;
        Group = serviceUser;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        InaccessiblePaths = [
          "-/run/wrappers/bin/op"
          "-${credentialDirectory}"
        ];
        ReadWritePaths = [ stateRoot ];
        KillMode = "mixed";
        Restart = "always";
        RestartSec = "5s";
        TimeoutStopSec = "30s";
      };
    };

    systemd.services.${serviceName} = {
      description = "OAuth-protected Bunnings PowerPass invoice MCP server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "${browserServiceName}.service"
      ];
      requires = [ "${browserServiceName}.service" ];
      wants = [ "network-online.target" ];

      script =
        let
          scopeArgs = lib.concatMapStringsSep " " (
            scope: "--required-scope ${lib.escapeShellArg scope}"
          ) cfg.oauth.requiredScopes;
        in
        ''
          exec ${lib.getExe cfg.gatewayPackage} \
            --backend-command ${lib.escapeShellArg (lib.getExe backend)} \
            --resource-name ${lib.escapeShellArg "Bunnings PowerPass Invoices"} \
            --listen-address ${lib.escapeShellArg cfg.listenAddress} \
            --port ${toString cfg.port} \
            --path ${lib.escapeShellArg cfg.mcpPath} \
            --public-url ${lib.escapeShellArg cfg.publicUrl} \
            --issuer ${lib.escapeShellArg cfg.oauth.issuer} \
            --jwks-uri ${lib.escapeShellArg cfg.oauth.jwksUri} \
            --audience ${lib.escapeShellArg cfg.oauth.audience} \
            ${scopeArgs}
        '';

      environment = {
        FASTMCP_CHECK_FOR_UPDATES = "off";
        FASTMCP_MASK_ERROR_DETAILS = "true";
        HOME = stateRoot;
        XDG_STATE_HOME = stateRoot;
      };

      serviceConfig = hardening // {
        User = serviceUser;
        Group = serviceUser;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        RuntimeDirectory = serviceName;
        RuntimeDirectoryMode = "0700";
        InaccessiblePaths = [
          "-/run/wrappers/bin/op"
          "-${credentialDirectory}"
        ];
        ReadWritePaths = [ stateRoot ];
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
