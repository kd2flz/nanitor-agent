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
      description = "Log level (exported as NANITOR_LOG_LEVEL).";
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

    # Keep the config file managed, even if the agent doesn't consume it directly.
    configPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nanitor/agent.conf";
      description = "Rendered config path (for reference).";
    };

    settingsFormat = lib.mkOption {
      type = lib.types.enum [ "raw" "json" "toml" "yaml" "ini" ];
      default = "raw";
      description = "Format used to render `settings` into the config file.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Structured settings; rendered according to `settingsFormat`.";
    };

    settingsText = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw config file content (used when settingsFormat=raw).";
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
    users.groups.${cfg.group} = {};
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "Nanitor Agent";
    };

    # Render /etc/nanitor/agent.conf (for reference).
    environment.etc."nanitor/agent.conf" =
      let
        rendered =
          if cfg.settingsFormat == "raw" then cfg.settingsText
          else if cfg.settingsFormat == "json" then builtins.toJSON cfg.settings
          else if cfg.settingsFormat == "toml" then (pkgs.formats.toml { }).generate "agent.conf" cfg.settings
          else if cfg.settingsFormat == "yaml" then (pkgs.formats.yaml { }).generate "agent.conf" cfg.settings
          else lib.generators.toINI {} cfg.settings;
      in {
        text = rendered;
        mode = "0640";
        user = cfg.user;
        group = cfg.group;
      };

    systemd.services.nanitor-agent = {
      description = "Nanitor Security Agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        StateDirectory = "nanitor";   # /var/lib/nanitor
        LogsDirectory = "nanitor";    # /var/log/nanitor
        RuntimeDirectory = "nanitor"; # /run/nanitor

        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") (
          cfg.environment // {
            NANITOR_LOG_LEVEL = cfg.logLevel;
            NANITOR_DATA_DIR = cfg.dataDir;
          }
        );

        # ✅ Correct start command (no --config)
        ExecStart = "${cfg.package}/bin/nanitor-agent start";

        Restart = "always";
        RestartSec = "5s";

        # Optional hardening (tune once tested)
        # NoNewPrivileges = true;
        # ProtectSystem = "strict";
        # ProtectHome = true;
        # SystemCallFilter = [ "@system-service" ];
      };

      # Enrollment & health hooks
      # We wrap logic in a bash script so it's readable and robust.
      # Note: Runs as the service's User (cfg.user). If 'signup' needs root, set 'User=root' or use 'ExecStartPre' with 'sudo'—but generally try to keep it unprivileged.
      script = let
        bin = "${cfg.package}/bin/nanitor-agent";
      in ''
        set -euo pipefail

        log() { echo "[nanitor-agent unit] $*"; }

        # Optionally set server URL
        if [ "${lib.boolToString (cfg.enroll.enable && cfg.enroll.serverUrl != null)}" = "true" ]; then
          log "Setting server URL to '${cfg.enroll.serverUrl}'"
          ${bin} set-server-url ${lib.escapeShellArg cfg.enroll.serverUrl} || log "set-server-url failed (continuing)"
        fi

        # If not enrolled, run signup
        if [ "${lib.boolToString cfg.enroll.enable}" = "true" ]; then
          if ! ${bin} is-signedup >/dev/null 2>&1; then
            log "Not enrolled yet; attempting signup"
            ${bin} signup || log "signup failed; agent may not connect"
          else
            log "Agent already enrolled"
          fi
        fi
      '';

      # Run enrollment before start
      preStart = ''
        ${pkgs.bash}/bin/bash -c '${lib.escapeShellArg (lib.getAttr "script" config.systemd.services.nanitor-agent)}'
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

      # Wire the script hooks to the unit
      # (systemd's declarative support is limited—use serviceConfig + unit-level hooks.)
      unitConfig = {
        # Nothing here; we used service-level preStart/postStart via mkOrder.
      };

      # Bind the hooks
      # NixOS exposes service-level extra commands with these options:
      #   - preStart / postStart (wrapped by NixOS to ExecStartPre/ExecStartPost)
      # See: NixOS manual on "systemd.services.<name>.*Start" hooks.
    };
  };
}
