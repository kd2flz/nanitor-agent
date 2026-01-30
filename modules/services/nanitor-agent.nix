
{ config, lib, pkgs, ... }:
let
  cfg = config.services.nanitor-agent;
in
{
  options.services.nanitor-agent = {
    enable = lib.mkEnableOption "Nanitor agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nanitor-agent;
      description = "Package providing the Nanitor agent binary.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "nanitor";
      description = "System user to run the Nanitor agent.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "nanitor";
      description = "System group for the Nanitor agent.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nanitor";
      description = "Data/state directory used by the agent.";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
      description = "Log level written to /etc/nanitor/nanitor_agent.ini as 'loglevel' in the [logging] section.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Extra environment variables for the agent (e.g., ENROLL_TOKEN, ENDPOINT).";
      example = {
        NANITOR_ENROLL_TOKEN = "abc123";
        NANITOR_ENDPOINT = "https://api.nanitor.example";
      };
    };

    configPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nanitor/nanitor_agent.ini";
      description = "Rendered config path (for reference).";
    };

    settingsText = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra lines appended to the [logging] section of /etc/nanitor/nanitor_agent.ini.";
    };

    enroll.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run 'signup' automatically if not enrolled.";
    };

    enroll.serverUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "If set, runs 'set-server-url <url>' before signup.";
    };

    healthCheck.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Verify agent status/enrollment after start.";
    };

    healthCheck.timeoutSec = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Max seconds to wait for health check (is-signedup/info).";
    };
  };

  config = lib.mkIf cfg.enable {

    # Only create non-root user/group if configured (service runs as root by default).
    users.groups = lib.mkIf (cfg.group != "root") { ${cfg.group} = {}; };
    users.users  = lib.mkIf (cfg.user  != "root") {
      ${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.dataDir;
        description = "Nanitor Agent";
      };
    };

    # /etc/nanitor/nanitor_agent.ini managed via environment.etc
    environment.etc."nanitor/nanitor_agent.ini" = {
      text = ''
        [logging]
        loglevel = ${cfg.logLevel}
        ${cfg.settingsText}
      '';
      mode = "0640";
      user = "root";
      group = "root";
    };
    # (environment.etc is the canonical way to manage files under /etc on NixOS.)  # [5](https://unix.stackexchange.com/questions/500025/how-to-add-a-file-to-etc-in-nixos)[6](https://mynixos.com/nixpkgs/option/environment.etc)

    systemd.services.nanitor-agent = {
      description = "Nanitor Security Agent";

      # Provide runtime tools via systemd's path option (adds bin/sbin to PATH).
      path = with pkgs; [ python3 dmidecode ];  # [1](https://mynixos.com/nixpkgs/option/systemd.services.%3Cname%3E.path)

      after    = [ "network-online.target" ];
      wants    = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type  = "simple";
        User  = "root";   # Agent requires admin privileges.
        Group = "root";   # Match User.

        # These systemd-managed directories will be created under /var/{lib,log,run}/nanitor
        StateDirectory  = "nanitor";
        LogsDirectory   = "nanitor";
        RuntimeDirectory= "nanitor";

        # No manual PATH needed; 'path = [...]' above handles it.  # [1](https://mynixos.com/nixpkgs/option/systemd.services.%3Cname%3E.path)
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") (
          cfg.environment // {
            NANITOR_DATA_DIR = cfg.dataDir;
          }
        );

        # Use the dataDir as working directory; it exists via StateDirectory (default matches).
        WorkingDirectory = cfg.dataDir;

        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart    = "on-failure";
        RestartSec = "42s";
      };

      # Enrollment hook before start (shell features OK via preStart).
      preStart =
        let
          bin = "${cfg.package}/bin/nanitor-agent";
          serverUrlScript =
            if cfg.enroll.serverUrl != null then ''
              echo "[nanitor-agent unit] Setting server URL to '${cfg.enroll.serverUrl}'"
              ${bin} set-server-url ${lib.escapeShellArg cfg.enroll.serverUrl} || echo "[nanitor-agent unit] set-server-url failed (continuing)"
            '' else "";
        in lib.mkIf cfg.enroll.enable ''
          set -euo pipefail
          ${serverUrlScript}
          if ! ${bin} is-signedup >/dev/null 2>&1; then
            echo "[nanitor-agent unit] Not enrolled yet; attempting signup"
            ${bin} signup || echo "[nanitor-agent unit] signup failed; agent may not connect"
          else
            echo "[nanitor-agent unit] Agent already enrolled"
          fi
        '';

      # Start command (using NixOS 'script' convenience so we can pass --config easily).
      script = ''
        exec ${cfg.package}/bin/nanitor-agent start --config ${config.environment.etc."nanitor/nanitor_agent.ini".source}
      '';  # (script expands to ExecStart with a generated shell wrapper.)  # [3](https://discourse.nixos.org/t/difference-systemd-executable-command-methods/36964)

      # Health check after start; fully-qualify 'timeout' to be safe.
      postStart = lib.mkIf cfg.healthCheck.enable ''
        ${pkgs.coreutils}/bin/timeout ${toString cfg.healthCheck.timeoutSec} ${pkgs.bash}/bin/bash -c '
          set -euo pipefail
          bin="${cfg.package}/bin/nanitor-agent"

          if ! "$bin" info >/dev/null 2>&1; then
            echo "[nanitor-agent unit] info failed"
            exit 1
          fi

          if ${lib.boolToString cfg.enroll.enable}; then
            if ! "$bin" is-signedup >/dev/null 2>&1; then
              echo "[nanitor-agent unit] not enrolled after start"
              exit 2
            fi
          fi

          echo "[nanitor-agent unit] health OK"
          exit 0
        '
      '';
    };
  };
}
