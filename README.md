# Nanitor agent - Nix Package and NixOS Module

## Module Structure
- Module: `modules/services/nanitor-agent.nix`
- Package: `pkgs/nanitor-agent/default.nix`

## How to Use (NixOS Config with Flakes)
In your system flake, add the nanitor agent flake as an input and use the exported module and package. Example snippet for `flake.nix` in your system repo:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  nanitor.url = "github:kd2flz/nanitor-agent/main";
};

outputs = { self, nixpkgs, nanitor, ... }:
{
  nixosModules = {
    myHost = import ./configuration.nix; # typical usage
  };

  # In your configuration.nix or modules list:
  # imports = [ nanitor.nixosModules.nanitor-agent ];

  # Then configure options:
  # services.nanitor-agent.enable = true;
  # services.nanitor-agent.package = nanitor.packages.x86_64-linux.nanitor-agent;
}
```

## Local Build
- Build the package or test the flake locally:
  `nix build .#packages.x86_64-linux.nanitor-agent`

## Module Options
- `services.nanitor-agent.enable` : enable service
- `services.nanitor-agent.package` : package providing the binary (defaults to `pkgs.nanitor-agent`)
- `services.nanitor-agent.dataDir` : data dir (default `/var/lib/nanitor`)
- `services.nanitor-agent.logLevel` : log level written to `/etc/nanitor/nanitor_agent.ini` (default `info`, options: `debug`, `info`, `warn`, `error`)
- `services.nanitor-agent.settingsText` : extra lines appended to the `[logging]` section of `/etc/nanitor/nanitor_agent.ini`
- `services.nanitor-agent.environment` : extra environment variables (e.g., `NANITOR_ENROLL_TOKEN`, `NANITOR_ENDPOINT`)
- `services.nanitor-agent.enroll.enable` : run auto-signup if not enrolled (default `true`)
- `services.nanitor-agent.enroll.serverUrl` : optional server URL to set before signup
- `services.nanitor-agent.healthCheck.enable` : run a health check after start (default `true`)

### Example with Debug Logging
```nix
services.nanitor-agent = {
  enable = true;
  logLevel = "debug";  # Writes loglevel = debug to /etc/nanitor/nanitor_agent.ini
  environment = {
    NANITOR_ENROLL_TOKEN = "your-token-here";
    NANITOR_ENDPOINT = "https://api.nanitor.example";
  };
  # Optionally add extra ini settings (e.g., proxy, etc.)
  settingsText = ''
    # proxy_url = http://proxy.example.com:8080
  '';
};

### Example with Custom File Logging Settings
If you want to explicitly control file logging parameters like `enable_console`, `enable_file`, and `logfile`, you can use `settingsText`:

```nix
services.nanitor-agent = {
  enable = true;
  logLevel = "info"; # Or your desired level
  settingsText = ''
    enable_console = false
    enable_file = true
    logfile = /var/log/nanitor/nanitor_agent.log
  '';
};
```

## Config File and Logging

The module automatically renders the `nanitor_agent.ini` configuration file. This file is typically symlinked from `/etc/nanitor/nanitor_agent.ini` to a specific path in the Nix store. The `nanitor-agent` service is configured to read from this Nix store path.

The rendered file contains a `[logging]` section with:
- `loglevel` : set from `services.nanitor-agent.logLevel`
- Any extra settings from `services.nanitor-agent.settingsText` will be appended to the `[logging]` section (if not specified otherwise by `settingsText`).

**To set the log level:**
In your NixOS configuration (e.g., `configuration.nix`), enable the service and set the desired `logLevel`:
```nix
services.nanitor-agent = {
  enable = true;
  logLevel = "debug"; # or "info", "warn", "error"
};
```
Then, rebuild your system:
```bash
sudo nixos-rebuild switch
```

**To verify the `loglevel` setting:**
First, identify the exact configuration file path being used by the agent:
```bash
# Get the ExecStart script path from the service unit
UNIT_SCRIPT_PATH=$(sudo systemctl cat nanitor-agent | grep ExecStart= | head -n 1 | awk '{print $1}' | cut -d'=' -f2)
# Extract the config file path from within that script
CONFIG_FILE_PATH=$(sudo cat "${UNIT_SCRIPT_PATH}" | grep -- '--config' | awk '{print $NF}')
echo "Agent is using config file: ${CONFIG_FILE_PATH}"
```
Then, inspect its contents:
```bash
sudo cat "${CONFIG_FILE_PATH}"
# This should show:
# [logging]
# loglevel = debug
```

**To retrieve logs:**
Logs are primarily handled by `journald` and also written to a file.

- **View logs from `journald` (recommended for real-time and recent logs):**
  - Tail logs interactively (live output):
    `sudo journalctl -u nanitor-agent -f`
  - View recent logs (e.g., last 15 minutes):
    `sudo journalctl -u nanitor-agent --since "15 minutes ago"`
  - View all logs for the service:
    `sudo journalctl -u nanitor-agent`

- **View logs from the file system:**
  Logs are written to `/var/log/nanitor/nanitor_agent.log`.
  ```bash
  sudo cat /var/log/nanitor/nanitor_agent.log
  sudo tail -f /var/log/nanitor/nanitor_agent.log
  ```

## Common troubleshooting commands (other than logging)
- See unit status:
  `sudo systemctl status nanitor-agent`

## Notes about the package
- The `pkgs/nanitor-agent` derivation in this repo fetches the vendor-provided binary. Verify `sha256` if you change the `url`.

## Notes about the package
- The `pkgs/nanitor-agent` derivation in this repo fetches the vendor-provided binary. Verify `sha256` if you change the `url`.
