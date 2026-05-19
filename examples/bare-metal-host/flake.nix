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

        ({ lib, ... }: {
          # Bare-metal essentials. Replace these with your real host
          # config (hardware-configuration.nix, bootloader, FS,
          # network, users, ...). The placeholders here only exist
          # so `nix eval` succeeds without a hardware-configuration.
          boot.loader.grub.enable = false;
          boot.loader.systemd-boot.enable = lib.mkDefault true;
          boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };

          networking.hostName = "demo";
          system.stateVersion = "25.11";

          users.users.alice = {
            isNormalUser = true;
            uid = 1000;
            extraGroups = [ "wheel" ];
          };

          # The Entra ID config. Single tenant, Intune-enrolled,
          # one mapped user.
          nixosEntraId = {
            enable = true;
            domain = [ "contoso.com" ];
            userMap.alice = "alice@contoso.com";
            joinType = "join";
            localUser = "alice";

            intuneCompliance = {
              enable = true;

              # Replace with values cribbed from a real supported
              # device's `dmidecode -t system,baseboard` output --
              # Intune treats anything matching "QEMU"/"Cloud
              # Hypervisor"/etc. as non-compliant.
              fakeDmi = {
                sys_vendor   = "Contoso Corp.";
                product_name = "ContosoBook 15";
                board_vendor = "Contoso Corp.";
                board_name   = "0XYZ1A";
              };
            };
          };

          # security.tpm2.enable + hardware.tpm... wiring goes here
          # on a real host so /dev/tpmrm0 exists and the `tss` group
          # is provisioned (the module adds himmelblaud to it).
          security.tpm2.enable = lib.mkDefault true;
        })
      ];
    };
  };
}
