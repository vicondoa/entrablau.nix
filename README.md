# nixos-entra-id

> ⚠️ **Pre-1.0.** APIs and option names may still change before
> `v0.1.0` is tagged in lockstep with [vicondoa/nixling] `v0.1.0`.
> The implementation **is** here today, but breaking changes are on
> the table until then. Pin to a commit SHA if you depend on it.

An **unofficial, framework-agnostic** community NixOS module bundle
for authenticating against Microsoft Entra ID (formerly Azure AD)
via [Himmelblau], with Intune device-compliance shimming.

## Project status

- **Stage:** pre-1.0, alpha — the lifted-from-`/etc/nixos` modules
  evaluate cleanly via `nix flake check`; tagged release coming with
  [vicondoa/nixling] `v0.1.0`.
- **Maintainer:** one person
- **Tested on:** NixOS unstable, x86_64-linux
- **CI:** none yet — landing in W6/W7 of the upstream refactor
- **Support:** best-effort, no SLA, no guarantees, pin to tagged
  releases
- **Endorsement:** not officially endorsed by Microsoft, Himmelblau,
  Microsoft Entra, NixOS, or Nixpkgs — independent community
  implementation

See [CHANGELOG.md](./CHANGELOG.md).

## What this is

A self-contained NixOS module you can use in any NixOS
configuration:

```nix
# In your flake.nix:
inputs.nixos-entra-id.url = "github:vicondoa/nixos-entra-id";

# In your NixOS / VM config:
imports = [ inputs.nixos-entra-id.nixosModules.default ];

nixosEntraId = {
  enable    = true;
  domain    = [ "contoso.com" ];
  userMap.alice = "alice@contoso.com";
  joinType  = "join";       # Intune-enrolled; use "register" for BYOD
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
```

What gets activated:

- The upstream Himmelblau NixOS module (PAM, NSS, broker, daemon)
  pointed at a TPM-enabled rebuild of the Himmelblau workspace
  (vendored in `pkgs/himmelblau-tpm/`).
- A user-map file at `/etc/himmelblau/user-map`.
- Firefox + the linux-entra-sso extension + `pinentry-qt` for the
  interactive auth UI.
- (If `intuneCompliance.enable` — default `true`) fake DMI / fake
  `/etc/os-release` bind-mounted **only into the himmelblau service
  mount namespaces**, plus the sandbox / address-family / FD-store
  overrides that real Intune enrolment requires.

## Framework-agnostic

This module **does not** depend on any VM framework. It composes:

- On a bare-metal NixOS host — see
  [`examples/bare-metal-host/`](./examples/bare-metal-host/).
- Inside a [vicondoa/nixling] microVM — see
  [`examples/inside-nixling-vm/`](./examples/inside-nixling-vm/).
- Inside any other NixOS-on-VM setup that imports modules normally.

The same option tree (`nixosEntraId.*`) is consumed either way.

## What's in the box

```
nixos-modules/
├── default.nix              <- option schema + sub-imports
├── himmelblau.nix           <- PAM/NSS/broker/daemon, user-map,
│                               Firefox SSO, pinentry-qt
└── intune-compliance.nix    <- fake DMI / os-release bind-mounts,
                                sandbox overrides, FileDescriptor-
                                StoreMax for PRT survival
pkgs/
└── himmelblau-tpm/          <- Himmelblau rebuilt with the `tpm`
                                cargo feature + two vendored crate
                                patches that make Intune CSR
                                validation pass
examples/
├── bare-metal-host/         <- minimal real flake (eval-tested)
└── inside-nixling-vm/       <- consumer-composition sketch
```

## Flake outputs

| Output | Use |
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
- **Not officially affiliated with NixOS / Nixpkgs** despite the
  `nixos-` repo-name prefix. The naming reflects the target OS, not
  any official-project status.

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

[vicondoa/nixling]: https://github.com/vicondoa/nixling
[Himmelblau]: https://github.com/himmelblau-idm/himmelblau
[nixling]: https://github.com/vicondoa/nixling

