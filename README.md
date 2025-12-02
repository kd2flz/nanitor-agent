# Nanitor agent - Nix packaging and NixOS module

A small repository containing the Nanitor agent package and a NixOS service module.

**Location:**
- Module: `modules/services/nanitor-agent.nix`
- Package: `pkgs/nanitor-agent/default.nix`

**Goals:**
- Provide a reproducible package for the Nanitor agent binary.
- Provide a NixOS module that exposes sensible defaults and hooks for enrollment and health checks.

**Quick Build / Rebuild (local development)**
- Build the package or test the flake locally:

  `nix build .#packages.x86_64-linux.nanitor-agent`

- If you use the module in a NixOS flake (your system config), update the flake lock and rebuild your system:

  ```bash
  cd /path/to/nanitor
  nix flake update

  # In your system config repo that imports this flake
  cd /path/to/nixos-config
  nix flake update
  sudo nixos-rebuild switch --flake .#your-hostname --impure
  ```

**Example: Importing the module from the flake**
In your system flake, add the nanitor flake as an input and use the exported module and package. Example snippet for `flake.nix` in your system repo:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  nanitor.url = "path:../nanitor"; # or a git/URL
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

**Module highlights / options**
- `services.nanitor-agent.enable` : enable service
- `services.nanitor-agent.package` : package providing the binary (defaults to `pkgs.nanitor-agent`)
- `services.nanitor-agent.user` / `group` : user and group (service runs as `root` because the agent requires admin privileges)
- `services.nanitor-agent.dataDir` : data dir (default `/var/lib/nanitor`)
- `services.nanitor-agent.environment` : extra environment variables (e.g., `NANITOR_ENROLL_TOKEN`)
- `services.nanitor-agent.enroll.enable` : run auto-signup if not enrolled
- `services.nanitor-agent.enroll.serverUrl` : optional server URL to set before signup
- `services.nanitor-agent.healthCheck.enable` : run a health check after start

**Systemd / service notes**
- The module uses NixOS systemd script helpers to run optional pre-start enrollment steps, the agent binary, and post-start health checks.
- The service must run as `root` (the agent requires admin rights).
- If you see "flag provided but not defined: -config", the system is still starting with an older wrapper/service. Ensure you:
  - Updated the flake lock (if your system imports this flake) with `nix flake update` in both repos.
  - Rebuilt the system with the updated flake: `sudo nixos-rebuild switch --flake /path/to/flake#hostname --impure`.

**Common troubleshooting commands**
- View recent logs (last 15 minutes):
  `sudo journalctl -u nanitor-agent --since "15 minutes ago"`
- Tail logs interactively:
  `sudo journalctl -u nanitor-agent -f`
- See unit status:
  `sudo systemctl status nanitor-agent`

**Notes about the package**
- The `pkgs/nanitor-agent` derivation in this repo may fetch the vendor-provided binary. Verify `sha256` if you change the `url`.
- If you have a wrapper script (e.g., `nanitor-agent-ctl`) be aware wrappers may pass arguments like `--config`; the typed agent binary used by the module must match the arguments expected by the real binary. The module intentionally calls the binary without `--config`.

**If you import this repo from another flake**
- Update the consumer flake's `flake.lock` after you update this repo: run `nix flake update` in both the `nanitor` flake and in the consumer flake that references it.
**Examples**

1) Flake-based system config (recommended)

Add `nanitor` as an input in your system flake and reference its exported module and package. Example snippet for a system `flake.nix`:

```nix
# flake.nix (system repo)
{
  description = "My NixOS system with Nanitor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nanitor.url = "path:../nanitor"; # or git+https URL
  };

  outputs = { self, nixpkgs, nanitor, ... }:
  let
    systems = [ "x86_64-linux" ];
  in {
    nixosConfigurations.myHost = forAll systems (system: let pkgs = import nixpkgs { inherit system; }; in
      pkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Use the module exported by the nanitor flake
          nanitor.nixosModules.nanitor-agent

          # ...other modules...
        ];
        configuration = {
          services.nanitor-agent.enable = true;
          services.nanitor-agent.package = nanitor.packages.${system}.nanitor-agent;
          services.nanitor-agent.enroll.enable = true;
          services.nanitor-agent.environment = {
            NANITOR_ENROLL_TOKEN = "replace-me";
            NANITOR_ENDPOINT = "https://api.nanitor.example";
          };
        };
      }
    );
  };
}
```

After editing the system flake, update the flake locks and rebuild your system:

```bash
cd /path/to/nanitor
nix flake update

cd /path/to/system-flake
nix flake update
sudo nixos-rebuild switch --flake .#myHost --impure
```

2) Non-flake / local import

If you prefer to import the module file directly (for quick testing), point to the module file in `modules`:

```nix
# configuration.nix fragment
{ config, pkgs, ... }:
{
  imports = [
    /path/to/nanitor/modules/services/nanitor-agent.nix
  ];

  services.nanitor-agent.enable = true;
  services.nanitor-agent.environment = {
    NANITOR_ENROLL_TOKEN = "replace-me";
  };
}
```

Notes
- The service must run as `root` (the agent needs admin privileges).
- If you still see an older unit passing `--config`, make sure you updated the consumer flake's `flake.lock` and rebuilt the system so the new unit text is installed.
- See the top-level `README.md` for quick troubleshooting commands (`journalctl`, `systemctl`).
