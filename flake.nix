{
  description = "Nanitor agent package and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };
        in
        {
          nanitor-agent = pkgs.callPackage ./pkgs/nanitor-agent {
            src = pkgs.fetchurl {
              url = "https://nanitor.io/agents/nanitor-agent-latest_amd64.deb";
              sha256 = "0nddiq3ps1icvhfpaq05mm04mb89a85jw1sw9582mr47rcqdddj8";
            };
          };

        }
      );

      nixosModules.nanitor-agent = import ./modules/services/nanitor-agent.nix;

    };
}
