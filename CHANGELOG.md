# Changelog

All notable changes to nixos-entra-id are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- Entra-backed NSS accounts whose shell is `/bin/bash` now work out of the
  box on NixOS. The module adds `/bin/bash` to `/etc/shells` and creates a
  tmpfiles symlink to `/run/current-system/sw/bin/bash`, preventing
  himmelblaud from rejecting cached accounts and falling back to interactive
  security-key authentication.

## [0.1.0] - 2026-05-19

First public alpha release.

**Scope:** Framework-agnostic NixOS modules for joining a VM (or any
NixOS host) to Microsoft Entra ID via Himmelblau, with optional
Intune device-compliance shimming.

**Composition:** designed to be imported per-VM via
`nixling.vms.<vm>.config.imports = [ inputs.nixos-entra-id.nixosModules.default ]`
when composed with [`vicondoa/nixling`][nixling] (also v0.1.0).
Standalone use on a bare-metal NixOS host is also supported; see
`examples/bare-metal-host/`.

**Stable in v0.1.0:**

- `nixosModules.default` (the `nixosEntraId.*` option tree).
- `nixosEntraId.himmelblau.*` — PAM / NSS / broker / daemon /
  user-map / Firefox SSO / pinentry-qt wiring.
- `nixosEntraId.intuneCompliance.*` — fake DMI / `/etc/os-release`
  bind-mount, `FileDescriptorStoreMax=1` for PRT survival,
  `RestrictAddressFamilies` widening, `ReadWritePaths` extension.
- `pkgs.himmelblau-tpm` — TPM-enabled Himmelblau build (workspace
  cargo feature + `libhimmelblau` PEM-CSR wrapping + `kanidm-hsm-crypto`
  X.509v3 KeyUsage / ExtendedKeyUsage patches).
- `flake.checks.<sys>.{eval-bare-metal,eval-disabled,eval-intune-off,
  himmelblau-tpm-drv}` — five gated outputs (four x86_64 + one
  aarch64 eval-disabled).
- License attribution: Apache-2.0 (this flake) + GPL-3.0-or-later
  (Himmelblau-derived outputs in `pkgs/himmelblau-tpm/`).
  See `THIRD-PARTY.md`.

[nixling]: https://github.com/vicondoa/nixling

### Added

- **`nixos-modules/`** — framework-agnostic NixOS module set, lifted
  from `/etc/nixos/modules/nixling/entra-id.nix` and split by
  concern:
  - `nixos-modules/default.nix` declares the `nixosEntraId.*`
    option tree and aggregates the two implementation files below.
  - `nixos-modules/himmelblau.nix` — Himmelblau workspace (PAM /
    NSS / broker / daemon / user-map / Firefox SSO + pinentry-qt
    wiring).
  - `nixos-modules/intune-compliance.nix` — Intune device-
    compliance shimming (fake DMI / `/etc/os-release` bind-mounts,
    `FileDescriptorStoreMax=1` for PRT survival,
    `RestrictAddressFamilies` widening for the tasks daemon's
    federation lookups, `ReadWritePaths` extension for ScriptsCSE).
- **`pkgs/himmelblau-tpm/`** — vendored TPM-enabled rebuild of
  Himmelblau (was `modules/nixling/ext/himmelblau-tpm/`). Patches
  the upstream `Cargo.nix` to propagate the `tpm` cargo feature to
  every workspace binary, plus two crate-source patches
  (`libhimmelblau` PEM-CSR wrapping + `kanidm-hsm-crypto` X.509v3
  KeyUsage / ExtendedKeyUsage extensions) that real-world Intune
  enrolment requires.
- **`flake.nix`**:
  - `nixosModules.default` is now a real module (imports the
    upstream Himmelblau NixOS module + our two new modules and
    applies the himmelblau-tpm overlay via `nixpkgs.overlays`).
  - `overlays.default` exposes `pkgs.himmelblauTpm` (an attrset of
    `{ daemon, broker, sso, pam, nss, aad-tool }`).
  - `packages.x86_64-linux.himmelblau-tpm` builds the TPM-enabled
    `aad-tool` diagnostic CLI; sub-binaries are exposed
    individually as `himmelblau-tpm-{daemon,broker,sso,pam,nss}`.
  - New input pin: `himmelblau` at upstream rev `b3c48849`, matching
    the `/etc/nixos` lock at extract time (the sed patches in
    `pkgs/himmelblau-tpm/` anchor on source lines from that rev).
- **`examples/bare-metal-host/`** — minimal real flake demonstrating
  `nixosEntraId.*` on a non-VM NixOS host. `nix flake check` and
  `nix eval ...drvPath` are both clean. The inline host module was
  extracted to its own `configuration.nix` so the top-level flake's
  `eval-bare-metal` check can reuse it without going through a child
  flake.
- **`examples/inside-nixling-vm/`** — README-only sketch showing the
  consumer-side composition with [vicondoa/nixling].
- **`flake.checks.<sys>`** — real assertions, not an empty attrset.
  Adds `eval-disabled` (arch-agnostic; asserts the module is a no-op
  when `nixosEntraId.enable = false`), `eval-intune-off` (x86_64-linux;
  asserts Himmelblau is wired but the Intune compliance shims do
  NOT fire when `intuneCompliance.enable = false`),
  `eval-bare-metal` (x86_64-linux; asserts the
  `examples/bare-metal-host/` config still evaluates), and
  `himmelblau-tpm-drv` (x86_64-linux; asserts the TPM-enabled
  `aad-tool` derivation evaluates without paying for a Rust
  compile). Each check is verified to actually fire when the
  guarded property is broken.
- **`THIRD-PARTY.md`** — per-component license breakdown for the
  Himmelblau-derived built outputs (GPL-3.0-or-later) and the two
  vendored crate patches (LGPL-3.0+ libhimmelblau and MPL-2.0
  kanidm-hsm-crypto). `pkgs.himmelblauTpm.*` now carries
  `meta.license = lib.licenses.gpl3Plus` so binary-cache redistributors
  see the obligations explicitly.

### Changed

- Option namespace rename: `nixling.entra-id.*` → `nixosEntraId.*`.
  Rationale: the new flake is framework-agnostic, so it cannot
  reference "nixling" in its public API. `fakeDmi` moves under
  `nixosEntraId.intuneCompliance.fakeDmi`. New
  `nixosEntraId.intuneCompliance.enable` (default `true`) gates the
  compliance shimming so a pure Azure-AD-Registered BYOD host that
  is not Intune-enrolled can disable it.
- README: rewritten from "skeleton, planned-API" framing to "use
  this today" framing, with the example imports + flake outputs
  documented inline. Added a "Quick start (10-minute path)" section
  with prerequisites, step-by-step rebuild + enrolment flow, and
  common gotchas.
- `flake.nix`: the overlay now uses `final.callPackage` (instead of
  raw `import`) so downstream consumers get the standard `.override`
  composition surface.
- `pkgs/himmelblau-tpm/`: renamed `AGENTS.md` to `MAINTAINING.md` and
  added an explicit "Maintainer notes; not user-facing" header.
  Generic-tenant wording replaces the previous "microsoft.com
  corporate" reference in the libhimmelblau-patch rationale.
- `nixos-modules/default.nix`: added `example =` fields on `joinType`
  and `intuneCompliance.enable` so the option-docs renderer has a
  suggested value in the right-hand column.

### Notes

- Architecture: x86_64-linux only for the package outputs and the
  overall verified path. The module set itself evaluates on
  aarch64-linux for completeness, but `pkgs.himmelblauTpm` is gated
  off there because the upstream Cargo.nix is x86_64-only and the
  Intune CSR enrolment path was not verified on aarch64.
- The first tagged release will be `v0.1.0`, shipping in lockstep
  with `vicondoa/nixling` v0.1.0. Until then, pin to a commit SHA.

## Bootstrap (pre-Phase-3, not tagged)

### Added

- Initial flake skeleton (Apache-2.0, x86_64-linux + aarch64-linux).
- This CHANGELOG.

[vicondoa/nixling]: https://github.com/vicondoa/nixling
