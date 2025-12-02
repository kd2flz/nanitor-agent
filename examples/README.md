# Examples — Using the `nanitor` flake

This file shows two minimal examples for consuming the `nanitor` repo/module:

1) Flake-based system config (recommended)

Add `nanitor` as an input in your system flake and reference its exported module and package.

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
