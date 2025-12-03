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
- `services.nanitor-agent.user` / `group` : user and group (service runs as `root` because the agent requires admin privileges)
- `services.nanitor-agent.dataDir` : data dir (default `/var/lib/nanitor`)
- `services.nanitor-agent.environment` : extra environment variables (e.g., `NANITOR_ENROLL_TOKEN`)
- `services.nanitor-agent.enroll.enable` : run auto-signup if not enrolled
- `services.nanitor-agent.enroll.serverUrl` : optional server URL to set before signup
- `services.nanitor-agent.healthCheck.enable` : run a health check after start

## Systemd / service notes
- The module uses NixOS systemd script helpers to run optional pre-start enrollment steps, the agent binary, and post-start health checks.
- The service must run as `root` (the agent requires admin rights).
- If you see "flag provided but not defined: -config", the system is still starting with an older wrapper/service. Ensure you:
  - Updated the flake lock (if your system imports this flake) with `nix flake update` in both repos.
  - Rebuilt the system with the updated flake: `sudo nixos-rebuild switch --flake /path/to/flake#hostname --impure`.

## Common troubleshooting commands
- View recent logs (last 15 minutes):
  `sudo journalctl -u nanitor-agent --since "15 minutes ago"`
- Tail logs interactively:
  `sudo journalctl -u nanitor-agent -f`
- See unit status:
  `sudo systemctl status nanitor-agent`

## Notes about the package
- The `pkgs/nanitor-agent` derivation in this repo fetches the vendor-provided binary. Verify `sha256` if you change the `url`.
