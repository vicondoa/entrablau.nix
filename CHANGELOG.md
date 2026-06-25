# Changelog

All notable changes to entrablau.nix are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `entrablau-sso-check` and `entrablau-sso-wait` readiness helpers,
  installed when `entrablau.enable = true`, for redacted Himmelblau /
  Entra SSO diagnostics and bounded waits before interactive auth.

## [1.0.0] - 2026-06-01

First stable release. The option namespace (`entrablau.*`) is now
stable; the pre-1.0 option root has been renamed (see migration table
below). No compatibility aliases for pre-1.0 option paths.

### Migration from 0.1.0

| Old (0.1.0) | New (1.0.0) | Notes |
|---|---|---|
| legacy option root | `entrablau.*` | **Breaking.** Rename the root key in your NixOS configuration to `entrablau`. No alias. |
| legacy DMI attribute under `intuneCompliance` | `intuneCompliance.dmiOverride` | Renamed for clarity; no alias |
| _(absent)_ | `intuneCompliance.osReleaseOverride` | New — whole-file `/etc/os-release` text override (bind-mounted into the Himmelblau service namespace) |
| legacy repository input | `inputs.entrablau.url = "github:vicondoa/entrablau.nix/v1.0.0"` | Repository renamed |

See [`docs/reference/options.md`](./docs/reference/options.md) for the
full option reference and migration table.

### Added

- `entrablau.intuneCompliance.dmiOverride` — replaces the pre-1.0
  DMI attribute.
  Administrator-declared DMI field values bind-mounted into the
  Himmelblau service mount namespaces.
- `entrablau.intuneCompliance.osReleaseOverride` — whole-file
  `/etc/os-release` text override (type `lines`) bind-mounted into
  the Himmelblau service namespace. The default is a complete
  Ubuntu 22.04.4 LTS `os-release` file.
- `docs/` tree: explanation, reference (options, GitHub Actions),
  how-to import guide.
- `AGENTS.md` — contributor / agent workflow documentation.
- `CONTRIBUTING.md` — contribution guidelines.
- `SECURITY.md` — vulnerability reporting, threat model, authorized-use
  disclaimer, sandbox relaxation documentation.

### Changed

- **Repository renamed** to `vicondoa/entrablau.nix`. The public
  option root has been renamed to `entrablau.*` (see migration
  table above).
- `README.md` rewritten for v1.0 with updated quick-start, What's
  Included table, and repository layout.
- `CHANGELOG.md` consolidated; pre-1.0 bootstrap entries removed.
- `THIRD-PARTY.md` updated to reference `entrablau.nix`.
- Framework-specific example material removed — this repo is
  framework-agnostic and does not carry framework-specific examples.

### Fixed

- Entra-backed NSS accounts whose shell is `/bin/bash` now work out of
  the box on NixOS. The module adds `/bin/bash` to `/etc/shells` and
  creates a tmpfiles symlink to `/run/current-system/sw/bin/bash`,
  preventing himmelblaud from rejecting cached accounts.

## [0.1.0] - 2026-05-19

First public alpha release.

**Scope:** Framework-agnostic NixOS modules for joining a NixOS host to
Microsoft Entra ID via Himmelblau, with optional Intune device-compliance
shimming.

**Stable in v0.1.0:**

- `nixosModules.default` (the `entrablau.*` option tree).
- `entrablau.himmelblau.*` — PAM / NSS / broker / daemon /
  user-map / Firefox SSO / pinentry-qt wiring.
- `entrablau.intuneCompliance.*` — DMI / `/etc/os-release`
  bind-mount, `FileDescriptorStoreMax=1` for PRT survival,
  `RestrictAddressFamilies` widening, `ReadWritePaths` extension.
- `pkgs.himmelblau-tpm` — TPM-enabled Himmelblau build (workspace
  cargo feature + `libhimmelblau` PEM-CSR wrapping + `kanidm-hsm-crypto`
  X.509v3 KeyUsage / ExtendedKeyUsage patches).
- `flake.checks.<sys>.{eval-bare-metal,eval-disabled,eval-intune-off,
  himmelblau-tpm-drv}` — four gated check outputs.
- License attribution: Apache-2.0 (this flake) + GPL-3.0-or-later
  (Himmelblau-derived outputs in `pkgs/himmelblau-tpm/`).

[Himmelblau]: https://github.com/himmelblau-idm/himmelblau
