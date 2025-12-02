
{
  description = "Nanitor agent package and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # or your preferred channel
  };

  outputs = { self, nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in {
      packages = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {          
            nanitor-agent = pkgs.callPackage ./pkgs/nanitor-agent {
            src = pkgs.fetchurl {
                url = "https://nanitor.io/agents/nanitor-agent-latest_amd64.deb";
                sha256 = "097qqq3w8h2h323gn8n468662y3s8y23k8kq9wrshxlyiwfz7igv";
            };
            };

        });

      nixosModules.nanitor-agent = import ./modules/services/nanitor-agent.nix;

      # Example NixOS configuration for quick test (optional)
      # nixosConfigurations.yourHost = nixpkgs.lib.nixosSystem {
      #   system = "x86_64-linux";
      #   modules = [
      #     ({ pkgs, ... }: {
      #       imports = [ self.nixosModules.nanitor-agent ];
      #       services.nanitor-agent.enable = true;
      #       services.nanitor-agent.package = self.packages.${pkgs.system}.nanitor-agent;
      #       services.nanitor-agent.environment = {
      #         NANITOR_ENROLL_TOKEN = "replace-me";
      #         NANITOR_ENDPOINT = "https://api.nanitor.example";
      #       };
      #       services.nanitor-agent.settingsFormat = "raw";
      #       services.nanitor-agent.settingsText = ''
      #         # Minimal config example; replace with real directives
      #         # endpoint = "https://api.nanitor.example"
      #         # enroll_token = "replace-me"
      #       '';
      #     })
      #   ];
      # };
    };
}
