
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
      description = ''
        Server URL to set before signup (e.g. "https://cci.nanitor.net/api").
        The value is used directly; use enroll.serverUrlFile if the URL is
        stored in a file (e.g. a sops-nix or agenix secret).
        Mutually exclusive with enroll.serverUrlFile.
      '';
    };

    enroll.serverUrlFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the server URL for enrollment.
        The URL is read from the file at runtime (leading/trailing whitespace
        is stripped). Use this instead of enroll.serverUrl when the URL is
        managed by a secret manager like sops-nix or agenix.
        Mutually exclusive with enroll.serverUrl.
      '';
    };

    enroll.key = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Signup key value (raw base64 string) for automatic enrollment.
        Mutually exclusive with enroll.keyFile.
        Can also be provided via NANITOR_ENROLL_TOKEN environment variable.
      '';
    };

    enroll.keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the signup key for automatic enrollment.
        The file may optionally contain PEM-style header/footer lines
        (-----BEGIN/END-----); these are stripped at runtime before the key
        is passed to the binary via --key.
        This is the recommended option when using secret managers like
        sops-nix or agenix, which provide secrets as files on disk.
        Mutually exclusive with enroll.key.
      '';
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

    assertions = [
      {
        assertion = !(cfg.enroll.key != null && cfg.enroll.keyFile != null);
        message = "services.nanitor-agent.enroll.key and services.nanitor-agent.enroll.keyFile are mutually exclusive.";
      }
      {
        assertion = !(cfg.enroll.serverUrl != null && cfg.enroll.serverUrlFile != null);
        message = "services.nanitor-agent.enroll.serverUrl and services.nanitor-agent.enroll.serverUrlFile are mutually exclusive.";
      }
    ];

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

    systemd.services.nanitor-agent = {
      description = "Nanitor Security Agent";

      # Provide runtime tools via systemd's path option (adds bin/sbin to PATH).
      # coreutils: tr, cat, etc.  gnugrep/gnused: grep, sed (used in preStart)
      path = with pkgs; [ python3 dmidecode coreutils gnugrep gnused ];

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
        RuntimeDirectory = "nanitor";

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

          # Read server URL from file at runtime if serverUrlFile is set.
          readServerUrlFileScript =
            if cfg.enroll.serverUrlFile != null then ''
              if [ ! -f ${lib.escapeShellArg cfg.enroll.serverUrlFile} ]; then
                echo "[nanitor-agent unit] ERROR: server URL file not found: ${lib.escapeShellArg cfg.enroll.serverUrlFile}"
                echo "[nanitor-agent unit] If using sops-nix or agenix, ensure the secret is available before this service starts."
                exit 1
              fi
              NANITOR_SERVER_URL=$(tr -d '[:space:]' < ${lib.escapeShellArg cfg.enroll.serverUrlFile})
              if [ -z "$NANITOR_SERVER_URL" ]; then
                echo "[nanitor-agent unit] ERROR: server URL file is empty: ${lib.escapeShellArg cfg.enroll.serverUrlFile}"
                exit 1
              fi
              export NANITOR_SERVER_URL
            '' else "";

          serverUrlScript =
            if cfg.enroll.serverUrlFile != null then ''
              echo "[nanitor-agent unit] Setting server URL from file"
              ${bin} set-server-url "$NANITOR_SERVER_URL" || echo "[nanitor-agent unit] set-server-url failed (continuing)"
            '' else if cfg.enroll.serverUrl != null then ''
              echo "[nanitor-agent unit] Setting server URL to '${cfg.enroll.serverUrl}'"
              ${bin} set-server-url ${lib.escapeShellArg cfg.enroll.serverUrl} || echo "[nanitor-agent unit] set-server-url failed (continuing)"
            '' else "";

          # Build the signup key argument based on the configured source.
          # Priority: keyFile > key > NANITOR_ENROLL_TOKEN env var
          # When keyFile is used, readKeyFileScript extracts the content into
          # $NANITOR_SIGNUP_KEY first (stripping PEM headers), so we reference that var.
          signupKeyArg =
            if cfg.enroll.keyFile != null then "--key \"$NANITOR_SIGNUP_KEY\""
            else if cfg.enroll.key != null then "--key ${lib.escapeShellArg cfg.enroll.key}"
            else if (cfg.environment.NANITOR_ENROLL_TOKEN or "") != "" then "--key \"$NANITOR_ENROLL_TOKEN\""
            else "";

          # When keyFile is set: validate the file, then read its content into
          # $NANITOR_SIGNUP_KEY for passing to the binary via --key.
          #
          # The Nanitor enrollment key format is a single-line PEM-like string:
          #   -----BEGIN ORGANIZATION SIGNUP KEY----- JWT + SIGNATURE -----END ORGANIZATION SIGNUP KEY-----
          #
          # The binary's --key flag expects the FULL string including the
          # -----BEGIN/END----- markers (confirmed: stripping them causes
          # "Header not found"; --keyfile causes "Invalid" due to trailing newline).
          # We read the file with tr -d '\r\n' to strip only newline characters,
          # preserving the markers and the internal " + " separator.
          readKeyFileScript =
            if cfg.enroll.keyFile != null then ''
              if [ ! -f ${lib.escapeShellArg cfg.enroll.keyFile} ]; then
                echo "[nanitor-agent unit] ERROR: key file not found: ${lib.escapeShellArg cfg.enroll.keyFile}"
                echo "[nanitor-agent unit] If using sops-nix or agenix, ensure the secret is available before this service starts."
                exit 1
              fi
              if [ ! -s ${lib.escapeShellArg cfg.enroll.keyFile} ]; then
                echo "[nanitor-agent unit] ERROR: key file is empty: ${lib.escapeShellArg cfg.enroll.keyFile}"
                exit 1
              fi
              NANITOR_SIGNUP_KEY=$(tr -d '\r\n' < ${lib.escapeShellArg cfg.enroll.keyFile})
              if [ -z "$NANITOR_SIGNUP_KEY" ]; then
                echo "[nanitor-agent unit] ERROR: key file is blank (contains only whitespace)"
                exit 1
              fi
              echo "[nanitor-agent unit] Key file read: ${lib.escapeShellArg cfg.enroll.keyFile}"
            '' else "";

        in lib.mkIf cfg.enroll.enable ''
          set -euo pipefail

          ${readKeyFileScript}
          ${readServerUrlFileScript}
          ${serverUrlScript}

          AGENT_UUID=$(${bin} info 2>/dev/null | grep "^UUID:" | sed 's/^UUID: *//' || true)
          if ! ${bin} is-signedup >/dev/null 2>&1 || [ -z "$AGENT_UUID" ]; then
            echo "[nanitor-agent unit] Not enrolled yet; attempting signup"
            ${bin} signup ${signupKeyArg} || echo "[nanitor-agent unit] signup failed; agent may not connect"
          else
            echo "[nanitor-agent unit] Agent already enrolled (UUID: $AGENT_UUID)"
          fi
        '';

      # Start command (using NixOS 'script' convenience so we can pass --config easily).
      script = ''
        exec ${cfg.package}/bin/nanitor-agent start --config ${config.environment.etc."nanitor/nanitor_agent.ini".source}
      '';  # (script expands to ExecStart with a generated shell wrapper.)  # [3](https://discourse.nixos.org/t/difference-systemd-executable-command-methods/36964)

      # Health check after start - just verify agent responds to info command.
      postStart = lib.mkIf cfg.healthCheck.enable ''
        ${pkgs.coreutils}/bin/timeout ${toString cfg.healthCheck.timeoutSec} ${pkgs.bash}/bin/bash -c '
          set -euo pipefail
          bin="${cfg.package}/bin/nanitor-agent"

          if ! "$bin" info >/dev/null 2>&1; then
            echo "[nanitor-agent unit] info failed"
            exit 1
          fi

          echo "[nanitor-agent unit] health OK"
          exit 0
        '
      '';
    };
  };
}
