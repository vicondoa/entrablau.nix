# entrablau.nix

An **unofficial, framework-agnostic** community NixOS flake for
authenticating against Microsoft Entra ID (formerly Azure AD) via
[Himmelblau], with optional Intune device-compliance shimming.

Import `nixosModules.default` into any NixOS configuration — bare-metal
host, VM guest, or container — and set a handful of options. The flake
wires the full Himmelblau stack (daemon, PAM, NSS, broker, Firefox SSO,
pinentry) against a TPM-enabled rebuild and optionally configures the
systemd sandbox overrides that real Intune enrolment requires.

## Project status

- **Stage:** v1.0 — stable public API (`entrablau.*`)
- **Maintainer:** one person
- **Tested on:** NixOS unstable, x86_64-linux
- **CI:** `nix flake check` gate; see [`docs/reference/github-actions.md`](./docs/reference/github-actions.md)
- **Support:** best-effort, no SLA, no guarantees — pin to a tagged release
- **Endorsement:** not officially endorsed by Microsoft, Himmelblau,
  Microsoft Entra, NixOS, or Nixpkgs — independent community
  implementation

See [CHANGELOG.md](./CHANGELOG.md).

## Quick start

Add the flake input to your NixOS configuration:

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
        entrablau.nixosModules.default
      ];
    };
  };
}
```

Then in your `configuration.nix`:

```nix
{ ... }: {
  security.tpm2.enable = true;

  users.users.alice = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  entrablau = {
    enable        = true;
    domain        = [ "contoso.com" ];
    userMap.alice = "alice@contoso.com";
    joinType      = "join";          # "register" for BYOD
    localUser     = "alice";

    intuneCompliance = {
      enable          = true;
      dmiOverride = {
        sys_vendor   = "Contoso Corp.";
        product_name = "ContosoBook 15";
        board_vendor = "Contoso Corp.";
        board_name   = "0XYZ1A";
      };
      # Optional: omit to use the module default. If set, provide a
      # complete os-release file.
      osReleaseOverride = ''
        PRETTY_NAME="Ubuntu 22.04.4 LTS"
        NAME="Ubuntu"
        VERSION_ID="22.04"
        VERSION="22.04.4 LTS (Jammy Jellyfish)"
        VERSION_CODENAME=jammy
        ID=ubuntu
        ID_LIKE=debian
      '';
    };
  };
}
```

Build and switch:

```bash
sudo nixos-rebuild build  --flake .#my-host
sudo nixos-rebuild switch --flake .#my-host
```

Trigger enrolment (or let PAM do it on first login):

```bash
aad-tool auth-test --name alice@contoso.com
```

Run `auth-test` from the real user's graphical terminal or another
session with a controlling TTY and user D-Bus session. The Hello PIN /
MFA prompt is interactive; running it from a headless root shell can
make the prompt path fail before credentials are requested.

Verify:

```bash
aad-tool tpm     # should report "Hardware TPM supported: true"
entrablau-sso-check
entrablau-sso-wait --upn alice@contoso.com --timeout 60
```

For a detailed walkthrough see
[`docs/how-to/import-into-nixos.md`](./docs/how-to/import-into-nixos.md).

### Common gotchas

- **`aad-tool tpm` reports "Hardware TPM supported was not enabled in
  this build"** → the `nixosModules.default` import did not take
  effect. Confirm the import is listed and the flake rebuilt.
  `which aad-tool` should resolve to
  `/run/current-system/sw/bin/aad-tool` → a `/nix/store/*-rust_aad-tool-*`
  path.
- **`himmelblaud` exits with `Permission denied` opening
  `/dev/tpmrm0`** → `security.tpm2.enable = true` is not set, or the
  `tss` group was not yet created. Reboot once after enabling TPM.
- **`auth-test` fails with `400 Bad Request: Value must be a valid
  PEM-encoded PKCS#10 CSR`** → the crate patches in
  `pkgs/himmelblau-tpm/` handle this; if it still fails, collect only
  redacted logs and never paste tokens, cookies, raw account JSON, or
  account IDs into an issue.
- **Firefox SSO doesn't kick in** → confirm `programs.firefox.enable`
  is `true`; the upstream Himmelblau module sets it but a local
  override to `false` disables the SSO extension policy.
- **`auth-test` or PAM returns `PAM_IGNORE` before prompting** → the
  daemon, user bus broker, NSS mapping, or Firefox native-messaging
  path may not be ready yet. Run `entrablau-sso-check` for a redacted
  readiness report, or `entrablau-sso-wait --upn <user@domain>` before
  starting an interactive authentication flow.
- **`himmelblaud-tasks` logs `federation provider not set`** →
  `entrablau.intuneCompliance.enable` is `false` or the rebuild
  didn't complete. The `RestrictAddressFamilies` widening is part of
  the compliance module.


## What's included

| Component | Description |
|---|---|
| `nixosModules.default` | Top-level module; wires all sub-components |
| Himmelblau daemon/PAM/NSS/broker | Upstream Himmelblau NixOS module pointed at the TPM-enabled rebuild |
| TPM-enabled Himmelblau packages | `pkgs.himmelblauTpm.*` — workspace rebuilt with the `tpm` cargo feature; two vendored crate patches for Intune CSR compatibility |
| Firefox SSO + native-messaging | `linux-entra-sso` WebExtension + managed policy, inherited from the upstream Himmelblau NixOS module |
| pinentry / UI glue | `pinentry-qt` wired for interactive Entra authentication prompts |
| SSO diagnostics | `entrablau-sso-check` and `entrablau-sso-wait` verify daemon, NSS, broker, native-messaging, and SSO-host readiness without printing tokens or raw account data |
| User-map | `/etc/himmelblau/user-map` generated from `entrablau.userMap` |
| Intune compliance service configuration | `himmelblaud-tasks.service` sandbox overrides (`RestrictAddressFamilies`, `ReadWritePaths`, `FileDescriptorStoreMax=1` for PRT survival) |
| DMI / OS-release overrides | `entrablau.intuneCompliance.dmiOverride` and `osReleaseOverride` supply administrator-declared DMI and OS-release values bind-mounted **only into the Himmelblau service mount namespaces** |

## Repository layout

```
nixos-modules/
├── default.nix              <- option schema + sub-imports
├── himmelblau.nix           <- PAM/NSS/broker/daemon, user-map,
│                               Firefox SSO, pinentry-qt
└── intune-compliance.nix    <- DMI/os-release bind-mounts,
                                sandbox overrides, FD-store shim
pkgs/
└── himmelblau-tpm/          <- TPM-enabled Himmelblau rebuild;
                                two vendored crate patches
examples/
└── bare-metal-host/         <- minimal real flake (eval-tested)
docs/
├── explanation/design.md    <- architecture rationale
├── reference/options.md     <- full option reference + migration
├── reference/github-actions.md <- CI / security posture
└── how-to/import-into-nixos.md <- step-by-step import guide
```

## Flake outputs

| Output | Description |
|---|---|
| `nixosModules.default` | `imports = [ ... ];` in any NixOS config |
| `overlays.default` | adds `pkgs.himmelblauTpm.{daemon,broker,...}` |
| `packages.x86_64-linux.himmelblau-tpm` | `nix build .#himmelblau-tpm` builds the TPM-enabled `aad-tool` for diagnostics |
| `packages.x86_64-linux.himmelblau-tpm-{daemon,broker,sso,pam,nss}` | individual workspace binaries |

aarch64 is not supported today — the upstream Himmelblau Cargo.nix is
wired for x86_64-linux only, and the Intune CSR enrolment path was
not verified on aarch64. The module evaluation works on either arch;
only the TPM-enabled rebuild is gated.

## What this is NOT

- **Not a security boundary.** Tooling that satisfies Intune
  compliance is, by design, fingerprintable as that tooling. This is
  a *compatibility* layer, not anti-detection.
- **Not officially endorsed by Microsoft, Himmelblau, or Microsoft
  Entra.** Best-effort community implementation.
- **Not officially affiliated with NixOS / Nixpkgs.** The naming
  reflects the target OS, not any official-project status.

## License

This flake's own source — the NixOS modules under `nixos-modules/`,
the packaging glue under `pkgs/himmelblau-tpm/`, the `flake.nix`
wiring, and the examples — is licensed [Apache-2.0](./LICENSE).

The **built outputs** (`pkgs.himmelblauTpm.*`,
`packages.x86_64-linux.himmelblau-tpm*`) are derivative works of the
upstream [Himmelblau] workspace (GPL-3.0-or-later) and are themselves
GPL-3.0-or-later. Apache-2.0 is one-way-compatible with GPL-3.0, so
the combination is clean, but anyone redistributing the **binaries**
(for example in a binary cache or a closed-source NixOS image) must
comply with GPL-3.0's source-availability obligations.

Consumers who let Nix build Himmelblau on-host from source satisfy
that obligation automatically: the upstream source lives in
`/nix/store/*-source` and is reachable from the resulting closure.

The two vendored crate patches keep their respective upstream
licenses — `libhimmelblau` 0.8.18 is LGPL-3.0-or-later;
`kanidm-hsm-crypto` 0.3.6 is MPL-2.0. Both are GPL-3.0-compatible.

Full breakdown: [THIRD-PARTY.md](./THIRD-PARTY.md).

[Himmelblau]: https://github.com/himmelblau-idm/himmelblau
