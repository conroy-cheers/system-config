{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.icloud-mail-mcp;
  mailGroup = "icloud-mail";
  mailRoot = "/var/lib/${cfg.stateDirectory}";
  maildir = "${mailRoot}/Maildir";

  mbsyncConfig = pkgs.writeText "icloud-mail-mbsyncrc" ''
    IMAPAccount icloud
    Host ${cfg.imapHost}
    Port 993
    User ${cfg.userName}
    PassCmd "${lib.getExe' pkgs.coreutils "cat"} \"$CREDENTIALS_DIRECTORY/icloud-password\""
    TLSType IMAPS

    IMAPStore icloud-remote
    Account icloud

    MaildirStore icloud-local
    Path ${maildir}/
    Inbox ${maildir}/INBOX
    SubFolders Verbatim

    Channel icloud
    Far :icloud-remote:
    Near :icloud-local:
    Patterns *
    Sync Pull
    Create Near
    Remove None
    Expunge None
    SyncState *
  '';

  notmuchConfig = pkgs.writeText "icloud-mail-notmuch-config" ''
    [database]
    path=${maildir}

    [user]
    name=${cfg.realName}
    primary_email=${cfg.address}
    other_email=${lib.concatStringsSep ";" cfg.aliases}

    [new]
    tags=new;unread;inbox
    ignore=

    [search]
    exclude_tags=deleted;spam;junk

    [maildir]
    synchronize_flags=false
  '';

  mcpConfig = pkgs.writeText "icloud-mail-mcp-config.toml" ''
    [notmuch]
    binary = "${lib.getExe pkgs.notmuch}"
    config = "${notmuchConfig}"

    [limits]
    max_body_chars = ${toString cfg.maxBodyChars}
    max_attachment_chars = ${toString cfg.maxAttachmentChars}
    max_image_bytes = ${toString cfg.maxImageBytes}

    [scopes]
    default = "mail"

    [scopes.mail]
    query = "not tag:deleted and not tag:spam and not tag:junk"
    description = "iCloud mail excluding deleted, spam, and junk"

    [identity]
    addresses = ${builtins.toJSON ([ cfg.address ] ++ cfg.aliases)}
  '';

  mcpCommand = pkgs.writeShellApplication {
    name = "icloud-mail-mcp-backend";
    runtimeInputs = [
      cfg.package
      pkgs.notmuch
      pkgs.pandoc
      pkgs.poppler-utils
    ];
    text = ''
      exec mcp-server-notmuch --config ${mcpConfig}
    '';
  };

  hardening = {
    CapabilityBoundingSet = "";
    DevicePolicy = "closed";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
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
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    UMask = "0027";
  };
in
{
  options.services.icloud-mail-mcp = {
    enable = lib.mkEnableOption "an iCloud Maildir/notmuch mirror with MCP access";

    package = lib.mkPackageOption pkgs "mcp-server-notmuch" { };

    address = lib.mkOption {
      type = lib.types.str;
      default = "conroy.cheers@icloud.com";
      description = "Primary iCloud email address.";
    };

    aliases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional addresses belonging to the mailbox owner.";
    };

    realName = lib.mkOption {
      type = lib.types.str;
      default = "Conroy Cheers";
      description = "Mailbox owner's display name.";
    };

    userName = lib.mkOption {
      type = lib.types.str;
      default = "conroy.cheers";
      description = "iCloud IMAP login name.";
    };

    imapHost = lib.mkOption {
      type = lib.types.str;
      default = "imap.mail.me.com";
      description = "iCloud IMAP server.";
    };

    smtp = {
      enable = lib.mkEnableOption "sending mail through iCloud SMTP";

      host = lib.mkOption {
        type = lib.types.str;
        default = "smtp.mail.me.com";
        description = "iCloud SMTP submission server.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "iCloud SMTP submission port using STARTTLS.";
      };

      userName = lib.mkOption {
        type = lib.types.str;
        default = "conroy.cheers@icloud.com";
        description = "Full iCloud address used for SMTP authentication.";
      };

      sendScope = lib.mkOption {
        type = lib.types.str;
        default = "mail.send";
        description = "OAuth scope required specifically by the send_email tool.";
      };

      maxRecipients = lib.mkOption {
        type = lib.types.ints.positive;
        default = 20;
        description = "Maximum number of unique recipients per message.";
      };

      maxSubjectChars = lib.mkOption {
        type = lib.types.ints.positive;
        default = 998;
        description = "Maximum subject length accepted by the send_email tool.";
      };

      maxBodyChars = lib.mkOption {
        type = lib.types.ints.positive;
        default = 200000;
        description = "Maximum plain-text body length accepted by the send_email tool.";
      };

      maxMessagesPerHour = lib.mkOption {
        type = lib.types.ints.positive;
        default = 20;
        description = "Process-local hourly limit for successfully submitted messages.";
      };

      attachments = {
        enable = lib.mkEnableOption "ChatGPT-managed file attachments";

        allowedHostSuffixes = lib.mkOption {
          type = lib.types.nonEmptyListOf lib.types.str;
          default = [ "oaiusercontent.com" ];
          description = "DNS suffixes from which the gateway may download ChatGPT-managed files.";
        };

        allowedAzureBlobAccountPrefixes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Azure Blob storage-account prefixes from which the gateway may download ChatGPT-managed files.";
        };

        maxCount = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = "Maximum number of attachments per message.";
        };

        maxFileBytes = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8 * 1024 * 1024;
          description = "Maximum raw size of one attachment.";
        };

        maxTotalBytes = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10 * 1024 * 1024;
          description = "Maximum total raw attachment size per message.";
        };

        maxEncodedMessageBytes = lib.mkOption {
          type = lib.types.ints.positive;
          default = 15 * 1024 * 1024;
          description = "Maximum serialized MIME message size after transfer encoding.";
        };

        maxRedirects = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 3;
          description = "Maximum number of validated redirects for one attachment download.";
        };

        connectTimeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = "Attachment download connection timeout.";
        };

        readTimeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 20;
          description = "Attachment download socket read timeout.";
        };

        overallTimeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 45;
          description = "Combined attachment download deadline for one send_email invocation.";
        };
      };
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = "File containing the iCloud app-specific password.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "icloud-mail";
      description = "Directory below /var/lib containing the Maildir and notmuch index.";
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Delay between completed mailbox synchronization runs.";
    };

    maxBodyChars = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100000;
      description = "Maximum message-body characters returned by one MCP call.";
    };

    maxAttachmentChars = lib.mkOption {
      type = lib.types.ints.positive;
      default = 250000;
      description = "Maximum extracted attachment characters returned by one MCP call.";
    };

    maxImageBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5242880;
      description = "Maximum image attachment size returned by one MCP call.";
    };

    gatewayPackage = lib.mkPackageOption pkgs "icloud-mail-mcp-gateway" { };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which the Streamable HTTP MCP endpoint listens.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8781;
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
        default = [ "mail.read" ];
        description = "OAuth scopes required on every MCP request.";
      };

      supportedScopes = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        default = [ "mail.read" ];
        description = "OAuth scopes advertised by the protected resource.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl && !lib.hasSuffix "/" cfg.publicUrl;
        message = "services.icloud-mail-mcp.publicUrl must be an HTTPS origin without a trailing slash.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.mcpPath;
        message = "services.icloud-mail-mcp.mcpPath must begin with a slash.";
      }
      {
        assertion = cfg.oauth.audience == "${cfg.publicUrl}${cfg.mcpPath}";
        message = "services.icloud-mail-mcp.oauth.audience must exactly match publicUrl plus mcpPath.";
      }
      {
        assertion = lib.all (scope: lib.elem scope cfg.oauth.supportedScopes) cfg.oauth.requiredScopes;
        message = "services.icloud-mail-mcp.oauth.requiredScopes must be included in supportedScopes.";
      }
      {
        assertion = !cfg.smtp.enable || lib.elem cfg.smtp.sendScope cfg.oauth.supportedScopes;
        message = "services.icloud-mail-mcp.smtp.sendScope must be included in oauth.supportedScopes.";
      }
      {
        assertion = !cfg.smtp.attachments.enable || cfg.smtp.enable;
        message = "services.icloud-mail-mcp.smtp.attachments requires SMTP sending to be enabled.";
      }
      {
        assertion =
          !cfg.smtp.attachments.enable
          || cfg.smtp.attachments.maxFileBytes <= cfg.smtp.attachments.maxTotalBytes;
        message = "services.icloud-mail-mcp.smtp.attachments.maxFileBytes must not exceed maxTotalBytes.";
      }
      {
        assertion =
          !cfg.smtp.attachments.enable
          || cfg.smtp.attachments.maxTotalBytes < cfg.smtp.attachments.maxEncodedMessageBytes;
        message = "services.icloud-mail-mcp.smtp.attachments.maxEncodedMessageBytes must exceed maxTotalBytes.";
      }
    ];

    users.groups.${mailGroup} = { };

    users.users.icloud-mail-sync = {
      isSystemUser = true;
      group = mailGroup;
      description = "Pull-only iCloud mailbox synchronization";
    };

    users.users.icloud-mail-mcp = {
      isSystemUser = true;
      group = mailGroup;
      description = "Read-only iCloud mailbox MCP access";
    };

    systemd.services.icloud-mail-sync = {
      description = "Pull iCloud mail and update the notmuch index";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = [
        pkgs.coreutils
        pkgs.isync
        pkgs.notmuch
      ];

      preStart = ''
        install -d -m 0750 ${maildir}
      '';

      script = ''
        grant_mcp_read_access() {
          find ${maildir} -type d ! -perm -0050 -exec chmod g+rx {} +
          find ${maildir} -type f ! -perm -0040 -exec chmod g+r {} +
        }

        trap grant_mcp_read_access EXIT
        mbsync --config ${mbsyncConfig} icloud
        grant_mcp_read_access
        notmuch --config=${notmuchConfig} new
        trap - EXIT
        grant_mcp_read_access
      '';

      serviceConfig = hardening // {
        Type = "oneshot";
        User = "icloud-mail-sync";
        Group = mailGroup;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0750";
        LoadCredential = "icloud-password:${cfg.passwordFile}";
        ReadWritePaths = [ mailRoot ];
      };
    };

    systemd.timers.icloud-mail-sync = {
      description = "Periodically pull iCloud mail";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitInactiveSec = cfg.syncInterval;
        Persistent = true;
        RandomizedDelaySec = "30s";
        Unit = "icloud-mail-sync.service";
      };
    };

    systemd.services.icloud-mail-mcp = {
      description = "OAuth-protected iCloud mail MCP server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      script =
        let
          gatewayArgs = [
            "--backend-command"
            (lib.getExe mcpCommand)
            "--listen-address"
            cfg.listenAddress
            "--port"
            (toString cfg.port)
            "--path"
            cfg.mcpPath
            "--public-url"
            cfg.publicUrl
            "--issuer"
            cfg.oauth.issuer
            "--jwks-uri"
            cfg.oauth.jwksUri
            "--audience"
            cfg.oauth.audience
          ]
          ++ lib.concatMap (scope: [
            "--required-scope"
            scope
          ]) cfg.oauth.requiredScopes
          ++ lib.concatMap (scope: [
            "--supported-scope"
            scope
          ]) cfg.oauth.supportedScopes
          ++ lib.optionals cfg.smtp.enable (
            [
              "--smtp-host"
              cfg.smtp.host
              "--smtp-port"
              (toString cfg.smtp.port)
              "--smtp-username"
              cfg.smtp.userName
              "--smtp-sender-address"
              cfg.address
              "--smtp-sender-name"
              cfg.realName
              "--smtp-send-scope"
              cfg.smtp.sendScope
              "--smtp-max-recipients"
              (toString cfg.smtp.maxRecipients)
              "--smtp-max-subject-chars"
              (toString cfg.smtp.maxSubjectChars)
              "--smtp-max-body-chars"
              (toString cfg.smtp.maxBodyChars)
              "--smtp-max-messages-per-hour"
              (toString cfg.smtp.maxMessagesPerHour)
            ]
            ++ lib.optionals cfg.smtp.attachments.enable (
              [
                "--smtp-attachments-enabled"
                "--smtp-max-attachments"
                (toString cfg.smtp.attachments.maxCount)
                "--smtp-max-attachment-bytes"
                (toString cfg.smtp.attachments.maxFileBytes)
                "--smtp-max-total-attachment-bytes"
                (toString cfg.smtp.attachments.maxTotalBytes)
                "--smtp-max-encoded-message-bytes"
                (toString cfg.smtp.attachments.maxEncodedMessageBytes)
                "--smtp-attachment-max-redirects"
                (toString cfg.smtp.attachments.maxRedirects)
                "--smtp-attachment-connect-timeout-seconds"
                (toString cfg.smtp.attachments.connectTimeoutSeconds)
                "--smtp-attachment-read-timeout-seconds"
                (toString cfg.smtp.attachments.readTimeoutSeconds)
                "--smtp-attachment-overall-timeout-seconds"
                (toString cfg.smtp.attachments.overallTimeoutSeconds)
              ]
              ++ lib.concatMap (host: [
                "--smtp-attachment-allowed-host"
                host
              ]) cfg.smtp.attachments.allowedHostSuffixes
              ++ lib.concatMap (prefix: [
                "--smtp-attachment-allowed-azure-blob-account-prefix"
                prefix
              ]) cfg.smtp.attachments.allowedAzureBlobAccountPrefixes
            )
          );
        in
        ''
          exec ${lib.getExe cfg.gatewayPackage} ${lib.escapeShellArgs gatewayArgs} ${lib.optionalString cfg.smtp.enable ''--smtp-password-file "$CREDENTIALS_DIRECTORY/icloud-password"''}
        '';

      environment = {
        FASTMCP_CHECK_FOR_UPDATES = "off";
        FASTMCP_MASK_ERROR_DETAILS = "true";
      };

      serviceConfig = hardening // {
        User = "icloud-mail-mcp";
        Group = mailGroup;
        RuntimeDirectory = "icloud-mail-mcp";
        RuntimeDirectoryMode = "0700";
        LoadCredential = lib.mkIf cfg.smtp.enable "icloud-password:${cfg.passwordFile}";
        MemoryMax = lib.mkIf cfg.smtp.attachments.enable "256M";
        ReadOnlyPaths = [ mailRoot ];
        Restart = "on-failure";
        RestartSec = "10s";
        UMask = "0077";
      };
    };
  };
}
