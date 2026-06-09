# Minimal NixOS host configuration demonstrating `entrablau.nix` on
# bare metal -- no microVM framework involved.
#
# To eval:
#   nix eval --no-write-lock-file \
#     path:./.#nixosConfigurations.demo.config.system.build.toplevel.drvPath
#
# To build (requires an x86_64-linux machine with the patches in
# pkgs/himmelblau-tpm/ matching the pinned himmelblau rev):
#   nix build --no-write-lock-file \
#     path:./.#nixosConfigurations.demo.config.system.build.toplevel
{
  description = "Bare-metal NixOS host with entrablau.nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    entrablau.url = "path:../..";
    entrablau.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, entrablau, ... }: {
    nixosConfigurations.demo = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        entrablau.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
