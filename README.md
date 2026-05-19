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

## Quick start (10-minute path)

End-to-end: from a fresh NixOS workstation to "I'm logged in to my
Entra tenant". Assumes you've already verified the prerequisites.

### Prerequisites

- NixOS unstable, **x86_64-linux** (the TPM-enabled Himmelblau
  rebuild is gated to x86_64-linux only — see *Flake outputs* below)
- A TPM 2.0 chip exposed at `/dev/tpmrm0`. Verify with:
  ```bash
  systemd-cryptenroll --tpm2-device=list
  ```
  You should see a `/dev/tpmrm0` entry. If not, enable TPM 2.0 in
  firmware and check `dmesg | grep -i tpm` for kernel-level
  initialisation errors.
- A Microsoft Entra tenant + an admin who can register the device
  (`Device Administrator` role at minimum; full `Global
  Administrator` is overkill).
- For Intune-managed tenants: a Conditional Access policy that does
  NOT block Linux clients outright. The compliance shimming makes the
  device *look* compatible to Intune; it does not bypass CA policies
  that explicitly require `Windows` or `macOS` device-OS values.

### Step 1: Add the flake input

In your system flake.nix. **`v0.1.0` is not tagged yet** — until it
is, pin to `main` or a commit SHA. Switch to `v0.1.0` once it ships.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pre-v0.1.0: track main (or pin a commit SHA for stability).
    nixos-entra-id.url = "github:vicondoa/nixos-entra-id";
    # Once tagged, switch to:
    # nixos-entra-id.url = "github:vicondoa/nixos-entra-id/v0.1.0";
    nixos-entra-id.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-entra-id, ... }: {
    nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
        nixos-entra-id.nixosModules.default
      ];
    };
  };
}
```

### Step 2: Configure the host

In `configuration.nix` (or any module that's imported into the host).
Replace the `TODO` markers with your tenant + user values; replace the
`fakeDmi` values with output cribbed from a real supported device's
`dmidecode -t system,baseboard`.

```nix
{ lib, ... }: {
  # Required for /dev/tpmrm0 + the `tss` group that himmelblaud's
  # DynamicUser is added to.
  security.tpm2.enable = true;

  users.users.alice = {                # TODO: rename `alice`
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  nixosEntraId = {
    enable        = true;
    domain        = [ "contoso.com" ]; # TODO: your tenant domain
    userMap.alice = "alice@contoso.com"; # TODO: local-user -> UPN
    joinType      = "join";            # "register" for BYOD
    localUser     = "alice";           # TODO

    intuneCompliance = {
      enable = true;
      fakeDmi = {                      # TODO: real supported device's DMI
        sys_vendor   = "Contoso Corp.";
        product_name = "ContosoBook 15";
        board_vendor = "Contoso Corp.";
        board_name   = "0XYZ1A";
      };
    };
  };
}
```

If you're on BYOD / Azure-AD-Registered (not Intune-enrolled), set
`intuneCompliance.enable = false` and skip the `fakeDmi` block.

### Step 3: Build BEFORE switching

```bash
sudo -A nixos-rebuild build --flake .#workstation
```

This produces `./result` (a system closure) without touching the
running system. If this fails — fix it now; `switch` will only be
harder to recover from. The build pulls in the TPM-enabled Himmelblau
rebuild (~10 minutes of Rust compile on a first build; cached after).

### Step 4: Switch

```bash
sudo -A nixos-rebuild switch --flake .#workstation
```

Activates the new generation. After this completes, `himmelblaud.service`
should be running.

### Step 5: Trigger enrolment

The Himmelblau workspace doesn't have a standalone `enroll` command at
the pinned upstream rev — enrolment happens lazily on the first
authentication. The easiest way to drive it deliberately is
`auth-test`, which runs the same enrol-then-authenticate flow that
PAM would on a graphical login:

```bash
sudo aad-tool auth-test --name alice@contoso.com
```

This is an interactive flow: a `pinentry-qt` window pops up for the
password / Hello PIN / MFA prompt. On success, the device receives a
client cert from the `Microsoft Intune Beta MDM Device CA` and the
sealed PRT is stored under `/var/lib/himmelblaud/`. (Running as root
is required when authenticating as a user other than the one calling
`aad-tool`.)

Equivalently, you can just `loginctl terminate-user $USER` and log in
again at SDDM/getty as `alice@contoso.com`; the PAM stack triggers
the same enrolment path.

### Step 6: Verify

```bash
# Show what aad-tool sees of the cached device state.
aad-tool tpm           # 'Hardware TPM supported: true' if step 5 worked
aad-tool status        # confirms himmelblaud is reachable
aad-tool auth-test --name alice@contoso.com  # idempotent re-auth

# Service health.
systemctl status himmelblaud
systemctl status himmelblaud-tasks       # Intune policy/compliance daemon
systemctl --user status himmelblau-broker  # dbus-activated, user scope

# Logs from the last few minutes.
journalctl -u himmelblaud -u himmelblaud-tasks --since "5 minutes ago"

# NSS lookup — should resolve the Entra UPN as a local user.
getent passwd alice@contoso.com
```

Try logging out and back in as your mapped user — your password is now
the Entra credential, and the cached PRT survives across restarts via
the `FileDescriptorStoreMax=1` shim.

### Common gotchas

- **`aad-tool tpm` reports "Hardware TPM supported was not enabled in
  this build"** → you're somehow not running the
  `pkgs.himmelblauTpm.aad-tool` from this flake. Check that
  `nixosModules.default` is actually imported and the rebuild used the
  resulting overlay. `which aad-tool` should resolve to
  `/run/current-system/sw/bin/aad-tool` → a `/nix/store/*-rust_aad-tool-*`
  path.
- **`himmelblaud` exits with `Permission denied` opening
  `/dev/tpmrm0`** → `security.tpm2.enable` is off, or the `tss` group
  isn't being created by the udev rule. Reboot once after enabling
  `security.tpm2.enable` (the rule fires at boot).
- **`auth-test` fails with `400 Bad Request: Value must be a valid
  PEM-encoded PKCS#10 CSR`** → you're hitting a strict Conditional-
  Access tenant. The two crate patches in `pkgs/himmelblau-tpm/`
  exist precisely to make this pass; if it still fails, capture the
  failing request body with `RUST_LOG=trace aad-tool auth-test …` and
  file an issue.
- **Firefox SSO doesn't kick in** → check that `programs.firefox.enable`
  is true (the upstream Himmelblau module sets it; if you've overridden
  it to false, the `linux-entra-sso` extension policy won't take
  effect). Re-open Firefox after the rebuild.
- **`himmelblaud-tasks` logs `Failed to apply Intune policies:
  federation provider not set`** → this means the `intune-compliance`
  module's `RestrictAddressFamilies` widening didn't apply. Confirm
  `nixosEntraId.intuneCompliance.enable = true` and rebuild.


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

