# Security policy — entrablau.nix

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | ✅ Yes |
| < 1.0.0 | ❌ No — upgrade to v1.0.0 |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Use [GitHub Security Advisories](https://github.com/vicondoa/entrablau.nix/security/advisories/new)
to report vulnerabilities privately. You will receive an
acknowledgement within 7 days. If you do not hear back, email the
maintainer (address on the GitHub profile).

Please include:

- A description of the vulnerability and its impact.
- Steps to reproduce or a proof-of-concept (if safe to share).
- The affected version(s) or commit range.
- Whether you believe a fix is straightforward.

We will coordinate disclosure and aim to publish a fix and advisory
within 90 days of the initial report, faster for critical issues.

## Threat model

### In scope

- **Nix module evaluation security:** a malicious `entrablau`
  option value that causes unexpected system configuration.
- **Service sandbox escapes:** a misconfiguration in the systemd
  sandbox directives that grants the Himmelblau services broader
  access than documented.
- **Credential exposure:** the DMI/OS-release override files written
  to the Nix store containing sensitive data that is accessible
  beyond the Himmelblau service namespaces.
- **Supply-chain issues in vendored crates:** the two patched crates
  in `pkgs/himmelblau-tpm/` introducing a vulnerability into the
  built binaries.

### Out of scope / non-goals

- Vulnerabilities in upstream Himmelblau itself — report those to
  <https://github.com/himmelblau-idm/himmelblau>.
- Vulnerabilities in `linux-entra-sso` — report those to
  <https://github.com/siemens/linux-entra-sso>.
- Bypassing Microsoft Entra ID or Intune authentication controls —
  this is not within the scope of this project.
- Host OS hardening outside of the Himmelblau service configuration.
- TPM attestation bypass — report to the relevant firmware vendor.

## Authorized-use disclaimer for DMI and OS-release overrides

`entrablau.intuneCompliance.dmiOverride` and
`entrablau.intuneCompliance.osReleaseOverride` allow a NixOS
system administrator to supply administrator-declared DMI field
values and OS-release values that are presented to Himmelblau's
service namespaces.

These overrides exist to satisfy Intune compliance checks on Linux
hosts that do not expose standard DMI values compatible with Intune's
device-compliance policies. They are **not** a bypass of Microsoft's
authentication or conditional-access enforcement. The values are
bind-mounted only into the `himmelblaud` and `himmelblaud-tasks`
service mount namespaces; they do not affect any other process or
the system's real DMI/OS-release.

Use of these overrides is the administrator's responsibility. Setting
values that misrepresent the device to violate your organization's
Acceptable Use Policy or Microsoft's terms of service is outside the
intended and authorized use of this module.

## Systemd sandbox relaxations

The Intune compliance module (`nixos-modules/intune-compliance.nix`)
applies the following systemd sandbox relaxations to the Himmelblau
services, which are required for real Intune enrolment. These are
documented here so administrators can make an informed decision.

| Service | Directive | Value | Reason |
|---|---|---|---|
| `himmelblaud-tasks` | `RestrictAddressFamilies` | `AF_INET AF_INET6 AF_UNIX` | Federation provider lookup requires outbound network; base NixOS Himmelblau module restricts to `AF_UNIX` only |
| `himmelblaud-tasks` | `ReadWritePaths` | `/var/lib/himmelblau` | ScriptsCSE policies write compliance artefacts here |
| `himmelblaud` | `FileDescriptorStoreMax` | `1` | Keeps the PRT file descriptor open across service restarts for credential survival |
| `himmelblaud`, `himmelblaud-tasks` | `BindPaths` | DMI sysfs paths and `/etc/os-release` | Override files from Nix store are bind-mounted into these namespaces only |

No `PrivilegeEscalation`, `NoNewPrivileges`, or `CapabilityBoundingSet`
relaxations are made. `ProtectSystem`, `ProtectHome`, and
`PrivateTmp` remain at their upstream-module defaults.

## Security advisories

Published advisories are available at
<https://github.com/vicondoa/entrablau.nix/security/advisories>.
