# Minimal NixOS host configuration demonstrating `nixos-entra-id` on
# bare metal -- no microVM framework involved. The same module also
# composes inside a nixling-managed VM (see
# `examples/inside-nixling-vm/`).
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
  description = "Bare-metal NixOS host with nixos-entra-id";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-entra-id.url = "path:../..";
    nixos-entra-id.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-entra-id, ... }: {
    nixosConfigurations.demo = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-entra-id.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
