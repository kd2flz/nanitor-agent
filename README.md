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
- `services.nanitor-agent.settingsText` : extra lines appended to the `[agent]` section of `/etc/nanitor/nanitor_agent.ini`
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
```

## Config File
The module automatically renders `/etc/nanitor/nanitor_agent.ini` with the `[agent]` section containing:
- `loglevel` : set from `services.nanitor-agent.logLevel`
- Any extra settings from `services.nanitor-agent.settingsText`

After rebuild, verify the config:
```bash
cat /etc/nanitor/nanitor_agent.ini
# Should show:
# [agent]
# loglevel = debug
```

Logs are written to `/var/log/nanitor/nanitor-agent.log`.

## Common troubleshooting commands
- View recent logs (last 15 minutes):
  `sudo journalctl -u nanitor-agent --since "15 minutes ago"`
- Tail logs interactively:
  `sudo journalctl -u nanitor-agent -f`
- See unit status:
  `sudo systemctl status nanitor-agent`

## Notes about the package
- The `pkgs/nanitor-agent` derivation in this repo fetches the vendor-provided binary. Verify `sha256` if you change the `url`.
