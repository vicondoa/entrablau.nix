# The host's NixOS module — extracted from the inline module in
# `flake.nix` so it can be reused by `entrablau.nix`'s flake.checks
# without re-running a sub-flake.
#
# Path: examples/bare-metal-host/configuration.nix
#
# This file is the unit of "the bare-metal example" that downstream
# eval-tests anchor on: if you edit this file, the `eval-bare-metal`
# check in the top-level flake re-asserts it composes.
{ lib, ... }:

{
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

      # Administrator-declared DMI values. Replace with values from
      # the real hardware's `dmidecode -t system,baseboard` output.
      dmiOverride = {
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
}
