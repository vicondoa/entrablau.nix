# Design explanation

## Goals

1. **Framework-agnostic:** the module must import into any NixOS
   configuration — bare-metal hosts, VM guests, containers — without
   depending on any specific VM framework or host orchestration layer.
2. **TPM-first:** all authentication flows use the TPM-backed PRT where
   a TPM 2.0 device is available. The flake provides a rebuilt Himmelblau
   workspace with the `tpm` cargo feature compiled in.
3. **Minimal attack surface:** the Intune compliance overrides (DMI,
   OS-release) are bind-mounted **only** into the Himmelblau service
   mount namespaces, not into the global mount namespace. No other
   process sees the overridden values.
4. **Stable public API:** the `entrablau.*` option tree is the only
   public interface. Internal implementation details (file paths,
   service names, overlay attrset structure) are not part of the
   public API and may change between minor versions.

## Module decomposition

```
nixosModules.default
├── imports upstream Himmelblau NixOS module
├── nixos-modules/himmelblau.nix        (PAM/NSS/broker/daemon/user-map/SSO)
└── nixos-modules/intune-compliance.nix (DMI/os-release/sandbox)
```

The upstream Himmelblau NixOS module handles PAM stack wiring, NSS
`passwd`/`group` entries, the broker socket, the `himmelblaud` system
service, Firefox managed-policy injection for `linux-entra-sso`, and
`pinentry-qt`. This flake's `himmelblau.nix` points the upstream module
at the TPM-enabled rebuild (`pkgs.himmelblauTpm`) via a `nixpkgs.overlays`
entry and wires the user-map file.

The `intune-compliance.nix` module is conditionally activated by
`entrablau.intuneCompliance.enable` (default `true`). It:

- Generates override files from `dmiOverride` and `osReleaseOverride`
  option values into the Nix store.
- Bind-mounts those files into the `himmelblaud` and `himmelblaud-tasks`
  service `BindPaths=` directives.
- Relaxes `RestrictAddressFamilies` on `himmelblaud-tasks` to allow the
  outbound federation provider lookups that Intune enrolment requires.
- Sets `FileDescriptorStoreMax=1` on `himmelblaud` so the PRT file
  descriptor survives service restarts.
- Extends `ReadWritePaths` on `himmelblaud-tasks` for ScriptsCSE
  compliance artefacts.

## TPM package build

`pkgs/himmelblau-tpm/` overrides the upstream Himmelblau flake's
`Cargo.nix` to propagate the `tpm` cargo feature to every workspace
binary. Two vendored crate sources are patched at build time:

- `libhimmelblau` — PEM-wraps the device-enrolment CSR bytes that the
  upstream code sends as raw DER. Required for Intune's strict
  `PKCS#10 PEM` validation.
- `kanidm-hsm-crypto` — adds X.509v3 `KeyUsage` (critical) and
  `ExtendedKeyUsage` (clientAuth) extensions to the TPM-generated CSR
  Subject. Required for Intune's certificate-profile acceptance.

The patches are applied via `sed` against the unpacked crate source at
Nix build time and are pinned to specific upstream source lines. If
upstream releases a new version, the patches must be re-verified.

## User-map

`entrablau.userMap` is an attrset mapping local NixOS user names to
Entra UPNs. The module renders this to `/etc/himmelblau/user-map`, which
the Himmelblau daemon uses to resolve PAM authentication to NSS accounts.
The mapping is many-to-one: multiple local users may map to the same UPN
(useful for shared service accounts), but one local user may only map to
one UPN.

## Intune compliance shimming

Intune's Linux compliance evaluation reads DMI fields (via `/sys/class/dmi/id/`)
and `/etc/os-release` to classify the device. On NixOS:

- The default `ID=nixos` in `/etc/os-release` is not in Intune's
  supported-OS list for most compliance policies.
- Virtual machines and custom hardware may expose DMI values that do not
  match any Intune-recognized hardware profile.

`dmiOverride` and `osReleaseOverride` allow the administrator to supply
values that Intune will accept. These overrides are **not** a bypass of
authentication; they are a compatibility layer. The device still
authenticates via the same Entra credential flow; only the
compliance-classification metadata is adjusted.

## Architecture decision: no compatibility aliases

When an option is renamed, the old name is removed without a
deprecation alias. This keeps the option tree clean and avoids
accumulating dead code. Callers must migrate explicitly. Migration
tables are documented in [`../reference/options.md`](../reference/options.md).
