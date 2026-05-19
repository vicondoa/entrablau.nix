# Inside a nixling-managed microVM

`nixos-entra-id` is a plain NixOS module — to use it inside a
[vicondoa/nixling] VM, the integration is a consumer-side composition.
Neither flake imports the other; the user glues them together in their
own configuration.

## Sketch

```nix
# consumer flake.nix
{
  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    nixling.url     = "github:vicondoa/nixling";
    nixling.inputs.nixpkgs.follows = "nixpkgs";

    nixos-entra-id.url = "github:vicondoa/nixos-entra-id";
    nixos-entra-id.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixling, nixos-entra-id, ... }: {
    nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixling.nixosModules.default

        {
          nixling.vms.work-aad = {
            graphics.enable = true;
            tpm.enable      = true;
            usbip.yubikey   = true;
            env   = "work";
            index = 10;

            # Glue: nixos-entra-id is a regular NixOS module, so it
            # imports into the VM's config like any other.
            config = {
              imports = [
                nixos-entra-id.nixosModules.default
                ./vms/work-aad.nix
              ];

              nixosEntraId = {
                enable    = true;
                domain    = [ "contoso.com" ];
                userMap.alice = "alice@contoso.com";
                joinType  = "join";
                localUser = "alice";

                intuneCompliance = {
                  enable = true;
                  fakeDmi = {
                    sys_vendor   = "Contoso Corp.";
                    product_name = "ContosoBook 15";
                    board_vendor = "Contoso Corp.";
                    board_name   = "0XYZ1A";
                  };
                };
              };
            };
          };
        }
      ];
    };
  };
}
```

## What's happening here

- `nixling.nixosModules.default` is the microVM framework: bridges,
  per-env NAT routers, swtpm, virtiofsd, the `nixling` CLI on the
  host.
- `nixling.vms.work-aad.config` is a regular NixOS module that's
  merged into the guest's configuration. Anything that goes there is
  the **guest's** NixOS config — bootloader, services, users, etc.
- `nixos-entra-id.nixosModules.default` is a regular NixOS module. We
  drop it in the guest's `imports`. From the module's perspective,
  it doesn't know or care whether the guest is a VM or a bare-metal
  host — same code path either way.

This is exactly the [framework-agnostic][1] design goal: the entra-id
module composes wherever NixOS does.

[vicondoa/nixling]: https://github.com/vicondoa/nixling
[1]: ../../README.md#framework-agnostic
