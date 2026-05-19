# Top-level entry point for the nixos-entra-id NixOS module.
#
# Declares the `nixosEntraId.*` option tree and imports the two
# concern-split implementation files:
#
#   himmelblau.nix         -- Himmelblau workspace (PAM, NSS, broker,
#                             daemon, TPM-enabled rebuild, user-map,
#                             Firefox SSO wiring).
#   intune-compliance.nix  -- shims that make Intune device-compliance
#                             actually pass on a NixOS guest (fake DMI,
#                             fake /etc/os-release, sandbox overrides,
#                             FileDescriptorStoreMax for PRT survival).
#
# This file does NOT import the upstream Himmelblau NixOS module nor
# apply the himmelblau-tpm overlay -- the flake-level wrapper
# (`nixosModules.default` in flake.nix) does that, because both depend
# on flake inputs that this module on its own cannot see.
{ lib, ... }:

{
  imports = [
    ./himmelblau.nix
    ./intune-compliance.nix
  ];

  options.nixosEntraId = {
    enable = lib.mkEnableOption "Himmelblau-backed Microsoft Entra ID authentication";

    domain = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "contoso.com" ];
      description = ''
        Tenant domain(s). The upstream Himmelblau module's type is
        `listOf str` even though most deployments pass exactly one
        entry. The @-suffix of each mapped UPN in `userMap` must match
        one of these domains.
      '';
    };

    userMap = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''{ alice = "alice@contoso.com"; }'';
      description = ''
        Map local-user → Entra UPN. Becomes `/etc/himmelblau/user-map`.
      '';
    };

    joinType = lib.mkOption {
      type = lib.types.enum [ "join" "register" ];
      default = "register";
      example = "join";
      description = ''
        `join` = Azure AD Joined (corporate-managed, Intune-enrolled).
        `register` = Azure AD Registered (BYOD). Conditional-access-
        strict tenants typically reject Registered devices, so use
        `join` when the tenant requires Intune compliance.
      '';
    };

    localUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        Name of the local user account that maps to an Entra UPN.
        Informational/diagnostic; the authoritative mapping is
        `userMap`.
      '';
    };

    intuneCompliance = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        # Set to false on Azure-AD-Registered BYOD hosts not enrolled
        # in Intune (keeps Himmelblau but drops the compliance shims).
        example = false;
        description = ''
          Whether to apply the Intune device-compliance shimming
          (fake DMI / `/etc/os-release` bind-mounts inside the
          himmelblau service mount namespaces, sandbox / address-
          family overrides, `FileDescriptorStoreMax=1` for PRT
          survival across restarts).

          Set to `false` if you only want the Himmelblau workspace
          (PAM / NSS / broker / daemon) without the Intune-specific
          tweaks -- e.g. a BYOD Azure-AD-Registered host that is not
          enrolled in Intune.
        '';
      };

      fakeDmi = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = lib.literalExpression ''
          {
            sys_vendor   = "Contoso Corp.";
            product_name = "ContosoBook 15";
            board_vendor = "Contoso Corp.";
            board_name   = "0XYZ1A";
          }
        '';
        description = ''
          DMI / SMBIOS values to bind-mount over `/sys/class/dmi/id/`
          inside the himmelblau service mount namespaces only.
          Defeats Intune compliance flagging a virtualised guest as
          `Cloud Hypervisor`/`KVM`/etc. Keys are sysfs filenames
          (`sys_vendor`, `product_name`, `board_vendor`,
          `board_name`, ...).
        '';
      };
    };
  };
}
