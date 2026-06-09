# How to import entrablau.nix into a NixOS configuration

This guide walks through adding `entrablau.nix` to an existing NixOS
configuration. It applies to any NixOS host — bare-metal, VM guest,
or other — that imports NixOS modules via flakes.

## Prerequisites

- NixOS with flakes enabled (`experimental-features = nix-command flakes`
  in `/etc/nix/nix.conf` or `nix.settings.experimental-features`).
- NixOS unstable channel (the TPM-enabled Himmelblau rebuild targets
  NixOS unstable; other channels may work but are not tested).
- x86_64-linux architecture for the package build outputs. The module
  itself evaluates on aarch64-linux but the Himmelblau binary is not
  built there.
- A TPM 2.0 chip accessible at `/dev/tpmrm0` (required for Intune
  enrolment; verify with `systemd-cryptenroll --tpm2-device=list`).
- A Microsoft Entra tenant and credentials to register/join a device.

## Step 1 — Add the flake input

In your top-level `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    entrablau.url = "github:vicondoa/entrablau.nix/v1.0.0";
    entrablau.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, entrablau, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
        entrablau.nixosModules.default   # <-- add this
      ];
    };
  };
}
```

`entrablau.inputs.nixpkgs.follows = "nixpkgs"` ensures both your
config and this flake use the same `nixpkgs` revision, avoiding
duplicate store paths.

## Step 2 — Enable TPM

In your NixOS configuration (`configuration.nix` or any imported
module):

```nix
security.tpm2.enable = true;
```

This creates the `tss` group and the udev rule that grants
`himmelblaud`'s `DynamicUser` access to `/dev/tpmrm0`. A single
reboot is required after enabling this for the udev rule to take
effect.

## Step 3 — Configure the module

```nix
{ ... }: {
  users.users.alice = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  entrablau = {
    enable        = true;
    domain        = [ "contoso.com" ];        # your Entra tenant domain
    userMap.alice = "alice@contoso.com";       # local user -> Entra UPN
    joinType      = "join";                    # "register" for BYOD
    localUser     = "alice";

    intuneCompliance = {
      enable = true;                           # set false for non-Intune BYOD
      dmiOverride = {
        sys_vendor   = "Contoso Corp.";
        product_name = "ContosoBook 15";
        board_vendor = "Contoso Corp.";
        board_name   = "0XYZ1A";
      };
      osReleaseOverride = {
        ID         = "ubuntu";
        VERSION_ID = "22.04";
      };
    };
  };
}
```

**`dmiOverride`:** supply DMI field values that your Intune tenant
recognizes as a compliant device. Obtain these from a reference device
that is already Intune-compliant: `dmidecode -t system,baseboard`.

**`osReleaseOverride`:** supply `ID` and `VERSION_ID` values that
match a supported OS in your Intune compliance policy. These are
bind-mounted only inside the Himmelblau service namespaces.

For BYOD / Azure-AD-Registered (not Intune-enrolled), set
`intuneCompliance.enable = false` and omit both override blocks.

## Step 4 — Build before switching

```bash
sudo nixos-rebuild build --flake .#my-host
```

This builds the full system closure (including the TPM-enabled
Himmelblau Rust workspace, ~10 min cold; cached thereafter) without
touching the running system. Fix any evaluation or build errors at
this stage.

## Step 5 — Switch

```bash
sudo nixos-rebuild switch --flake .#my-host
```

After completion, `himmelblaud.service` should be running:

```bash
systemctl status himmelblaud
```

## Step 6 — Trigger enrolment

Enrolment happens on the first authentication. You can trigger it
explicitly:

```bash
sudo aad-tool auth-test --name alice@contoso.com
```

A `pinentry-qt` window appears for the Entra credential / MFA prompt.
On success, a client certificate is issued by the Intune MDM CA and
the sealed PRT is stored under `/var/lib/himmelblaud/`.

Alternatively, log out and log in at the display manager as
`alice@contoso.com` — the PAM stack triggers the same enrolment path.

## Step 7 — Verify

```bash
aad-tool tpm                              # "Hardware TPM supported: true"
aad-tool status                           # himmelblaud reachable
systemctl status himmelblaud
systemctl status himmelblaud-tasks        # Intune policy daemon
systemctl --user status himmelblau-broker # user-scoped broker

# NSS lookup
getent passwd alice@contoso.com
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `aad-tool tpm` shows TPM not enabled | Module not imported or build used wrong overlay | Confirm `entrablau.nixosModules.default` is in `modules`; check `which aad-tool` points to Nix store |
| `Permission denied` on `/dev/tpmrm0` | `security.tpm2.enable` not set or udev rule not loaded | Set `security.tpm2.enable = true` and reboot |
| `400 Bad Request: Value must be a valid PEM-encoded PKCS#10 CSR` | Intune strict validation | Crate patches should handle this; capture `RUST_LOG=trace aad-tool auth-test …` and open an issue |
| Firefox SSO inactive | `programs.firefox.enable` overridden to `false` | Restore `programs.firefox.enable = true` |
| `himmelblaud-tasks` federation error | `intuneCompliance.enable = false` or rebuild incomplete | Set `intuneCompliance.enable = true` and rebuild |

## See also

- [`docs/reference/options.md`](../reference/options.md) — full option reference
- [`docs/explanation/design.md`](../explanation/design.md) — architecture rationale
- [`examples/bare-metal-host/`](../../examples/bare-metal-host/) — minimal eval-tested example
