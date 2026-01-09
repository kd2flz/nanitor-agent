{
  config,
  lib,
  pkgs,
  ...
}:
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
      default = { };
      description = "Extra environment variables for the agent (e.g., ENROLL_TOKEN, ENDPOINT).";
      example = {
        NANITOR_ENROLL_TOKEN = "abc123";
        NANITOR_ENDPOINT = "https://api.nanitor.example";
      };
    };

    # Keep the config file managed, even if the agent doesn't consume it directly.
    configPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nanitor/agent.conf";
      description = "Rendered config path (for reference).";
    };

    settingsText = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra lines appended to the [logging] section of /etc/nanitor/nanitor_agent.ini.";
    };

    # Enrollment controls & health checks
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
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "Nanitor Agent";
    };

    # Render /etc/nanitor/nanitor_agent.ini with agent configuration.
    environment.etc."nanitor/nanitor_agent.ini" = {
      text = ''
        [logging]
        loglevel = ${cfg.logLevel}
        ${cfg.settingsText}'';
      mode = "0640";
      user = "root"; # Config file owned by root for security
      group = "root";
    };

    systemd.services.nanitor-agent = {
      description = "Nanitor Security Agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "root"; # Reverting to root as the agent requires full admin rights
        Group = "root"; # Reverting to root as the agent requires full admin rights

        StateDirectory = "nanitor"; # /var/lib/nanitor, managed by systemd with root:root ownership
        LogsDirectory = "nanitor"; # /var/log/nanitor, managed by systemd with root:root ownership
        RuntimeDirectory = "nanitor"; # /run/nanitor, managed by systemd

        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") (
          cfg.environment
          // {
            NANITOR_DATA_DIR = cfg.dataDir;
            PATH = lib.makeBinPath [ cfg.package pkgs.dmidecode pkgs.python3 ] + ":${cfg.package}/bin:$\{PATH\}";
          }
        );

        WorkingDirectory = "${cfg.dataDir}/agent";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "42s";

        # Optional hardening (tune once tested)
        # NoNewPrivileges = true;
        # ProtectSystem = "strict";
        # ProtectHome = true;
        # SystemCallFilter = [ "@system-service" ];
      };

      # Enrollment hook before start
      preStart =
        let
          bin = "${cfg.package}/bin/nanitor-agent";
          serverUrlScript =
            if cfg.enroll.serverUrl != null then
              ''
                echo "[nanitor-agent unit] Setting server URL to '${cfg.enroll.serverUrl}'"
                ${bin} set-server-url ${lib.escapeShellArg cfg.enroll.serverUrl} || echo "[nanitor-agent unit] set-server-url failed (continuing)"
              ''
            else
              "";
        in
        lib.mkIf cfg.enroll.enable ''
          set -euo pipefail

          ${serverUrlScript}

          # If not enrolled, run signup
          if ! ${bin} is-signedup >/dev/null 2>&1; then
            echo "[nanitor-agent unit] Not enrolled yet; attempting signup"
            ${bin} signup || echo "[nanitor-agent unit] signup failed; agent may not connect"
          else
            echo "[nanitor-agent unit] Agent already enrolled"
          fi
        '';

      # Main start command
      script = ''
        exec ${cfg.package}/bin/nanitor-agent start --config ${config.environment.etc."nanitor/nanitor_agent.ini".source}
      '';

      # Health check after start
      postStart = lib.mkIf cfg.healthCheck.enable ''
        timeout ${toString cfg.healthCheck.timeoutSec} ${pkgs.bash}/bin/bash -c '
          set -euo pipefail
          bin="${cfg.package}/bin/nanitor-agent"

          # Try info first (quick sanity)
          if ! "$bin" info >/dev/null 2>&1; then
            echo "[nanitor-agent unit] info failed"
            exit 1
          fi

          # Enrollment check if enabled
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
