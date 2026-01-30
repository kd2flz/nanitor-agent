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
              sha256 = "129nwxgc7syn08wf4kkcmixzxs8l14xhb8r7ilgymvmb8zdpsnb4";
            };
          };

        }
      );

      nixosModules.nanitor-agent = import ./modules/services/nanitor-agent.nix;

    };
}
