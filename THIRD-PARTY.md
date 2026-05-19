# Third-party software and licenses

This flake's own source code (the NixOS modules under `nixos-modules/`,
the packaging glue under `pkgs/himmelblau-tpm/`, the flake.nix wiring,
and the examples) is licensed under [Apache-2.0](./LICENSE).

The **built outputs** that this flake produces — i.e. anything you get
from `nix build .#himmelblau-tpm*` or
`pkgs.himmelblauTpm.{daemon,broker,sso,pam,nss,aad-tool}` via the
overlay — are **derivative works of GPL-3.0 software** and are
themselves licensed GPL-3.0 (or later). Apache-2.0 is one-way-
compatible with GPL-3.0, so this combination is legally clean, but
downstream consumers who redistribute the built binaries (for example,
in a Nixpkgs binary cache or a closed-source NixOS image) MUST comply
with GPL-3.0's source-availability obligations.

If you only consume `nixosModules.default` and let Nix build the
Himmelblau binaries on-host from source, the source-availability
obligation is satisfied automatically (the source is fetched from the
upstream GitHub repos at build time and is available in
`/nix/store/*-source`).

## Components

### `pkgs.himmelblauTpm.{daemon,broker,sso,pam,nss,aad-tool}`

A TPM-enabled rebuild of the upstream Himmelblau workspace, with two
vendored-crate patches applied on top.

| Component | Upstream | License | Notes |
|---|---|---|---|
| Himmelblau workspace (aad-tool, daemon, broker, sso, pam, nss) | <https://github.com/himmelblau-idm/himmelblau> | GPL-3.0-or-later | The dominant component; sets the license of the combined output. Pinned to rev `b3c48849cc7b468e33b9e44bb1a1210e49e1391f` in this flake's `flake.lock`. |
| `libhimmelblau` 0.8.18 (vendored .crate, patched) | <https://gitlab.com/samba-team/libhimmelblau> | LGPL-3.0-or-later | Statically linked into the Himmelblau binaries. Patch: PEM-wrap the Intune device-enrolment CSR (see `pkgs/himmelblau-tpm/default.nix` for full rationale). |
| `kanidm-hsm-crypto` 0.3.6 (vendored .crate, patched) | <https://github.com/kanidm/hsm-crypto> | MPL-2.0 | Statically linked into the Himmelblau binaries. Patch: add X.509v3 KeyUsage (critical) + ExtendedKeyUsage (clientAuth) extensions to the TPM-generated CSR (see `pkgs/himmelblau-tpm/default.nix`). |

The combined binary is GPL-3.0-or-later because of the Himmelblau
workspace; LGPL-3.0+ and MPL-2.0 are both GPL-3.0-compatible upstream
licenses, so the link is clean.

### Patches kept in this repo (not vendored)

The two patches in `pkgs/himmelblau-tpm/default.nix` (sed surgery
against the unpacked vendored crates) and the `Cargo.nix` feature-
injection sed are **this repo's contribution**, licensed Apache-2.0.
The output of running them against the GPL-/LGPL-/MPL- sourced crates
is, of course, a derivative of those crates' source and inherits
their respective licenses.

### Browser SSO

The upstream Himmelblau NixOS module (imported by
`nixosModules.default`) configures Firefox to auto-install
[`linux-entra-sso`] <https://github.com/siemens/linux-entra-sso>, a
WebExtension licensed under GPL-3.0+ by Siemens. This flake doesn't
vendor or rebuild that extension — it's pulled at runtime from the
upstream GitHub release URL by the upstream Himmelblau module — but
it is part of the deployed system and worth noting.

## Trademark + endorsement disclaimer

"Microsoft", "Entra", "Azure AD", and "Intune" are trademarks of
Microsoft Corporation. This flake is not endorsed by, affiliated
with, or supported by Microsoft, the Himmelblau project, NixOS, or
Nixpkgs. See the top-level `README.md` "Project status" section.

[`linux-entra-sso`]: https://github.com/siemens/linux-entra-sso
