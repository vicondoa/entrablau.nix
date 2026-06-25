# Option reference — entrablau.*

This document covers the full `entrablau.*` option tree as of
v1.0.0 and the migration table from v0.1.0.

## Migration table: v0.1.0 → v1.0.0

| Old option (v0.1.0) | New option (v1.0.0) | Action required |
|---|---|---|
| legacy DMI attribute under `intuneCompliance` | `intuneCompliance.dmiOverride` | Rename the attribute in your configuration. No alias exists. |
| _(absent)_ | `intuneCompliance.osReleaseOverride` | Optional. Supply whole-file `/etc/os-release` text for the Himmelblau service namespace. |
| legacy repository input | `inputs.entrablau` | Update your flake input name and URL. |
| legacy repository URL | `github:vicondoa/entrablau.nix/v1.0.0` | Update the flake URL. |

There are no compatibility aliases. Configurations using the old
option names will fail to evaluate after upgrading to v1.0.0.

## Top-level options

### `entrablau.enable`

- **Type:** `bool`
- **Default:** `false`
- **Description:** Enable the entrablau.nix module. When `false`, all
  sub-options are ignored and no services, PAM entries, or NSS
  configuration is activated.

### `entrablau.domain`

- **Type:** `list of string`
- **Default:** `[]`
- **Description:** One or more Entra tenant domain names (e.g.,
  `[ "contoso.com" ]`). Passed to the Himmelblau configuration.

### `entrablau.joinType`

- **Type:** `enum [ "join" "register" ]`
- **Default:** `"register"`
- **Example:** `"join"`
- **Description:** `"join"` for Intune-enrolled (Azure AD joined)
  devices. `"register"` for BYOD (Azure AD registered) devices.

### `entrablau.localUser`

- **Type:** `null or string`
- **Default:** `null`
- **Description:** Name of the local NixOS user account that maps to an
  Entra UPN. Informational/diagnostic; the authoritative mapping is
  `userMap`.

### `entrablau.userMap`

- **Type:** `attrsOf string`
- **Default:** `{}`
- **Example:** `{ alice = "alice@contoso.com"; }`
- **Description:** Maps local NixOS user names to Entra UPNs. Rendered
  to `/etc/himmelblau/user-map`.

When `entrablau.enable = true`, the module also installs two
redacted readiness helpers:

- `entrablau-sso-check [--upn <upn>|--local-user <name>]` checks the
  Himmelblau daemon, optional tasks service, NSS mapping, `aad-tool
  status`, user D-Bus broker activation, `linux-entra-sso --help`, and
  Firefox native-messaging manifest host path.
- `entrablau-sso-wait [--upn <upn>|--local-user <name>] [--timeout
  <seconds>] [--interval <seconds>]` polls the same prerequisites with
  a bounded timeout for scripts that must wait before interactive
  authentication.

Both helpers suppress command output that could contain tokens,
cookies, raw account JSON, account IDs, or sensitive authentication
details. If `entrablau.localUser` names an entry in `userMap`, that UPN
is used as the default NSS check target; otherwise pass `--upn` or
`--local-user`.

---

## `entrablau.intuneCompliance`

### `entrablau.intuneCompliance.enable`

- **Type:** `bool`
- **Default:** `true`
- **Description:** Enable the Intune compliance shimming (DMI/OS-release
  bind-mounts, sandbox relaxations). Set to `false` for BYOD /
  Azure-AD-Registered hosts that are not Intune-enrolled.

### `entrablau.intuneCompliance.dmiOverride`

**Replaces the pre-1.0 DMI attribute. No alias.**

- **Type:** `attrsOf string`
- **Default:** `{}`
- **Description:** DMI field overrides bind-mounted into the Himmelblau
  service namespaces only. Keys map to sysfs DMI id filenames
  (e.g., `sys_vendor`, `product_name`, `board_vendor`, `board_name`).
  Values are the administrator-declared strings to present to
  Himmelblau/Intune.

  Example:
  ```nix
  dmiOverride = {
    sys_vendor   = "Contoso Corp.";
    product_name = "ContosoBook 15";
    board_vendor = "Contoso Corp.";
    board_name   = "0XYZ1A";
  };
  ```

  The overrides are written to the Nix store and bind-mounted at
  `/sys/class/dmi/id/<key>` in the service's private mount namespace.
  The host's real sysfs is unchanged.

### `entrablau.intuneCompliance.osReleaseOverride`

**New in v1.0.0.**

- **Type:** `lines`
- **Default:** complete Ubuntu 22.04.4 LTS `/etc/os-release` text.
- **Description:** `/etc/os-release` text bind-mounted into the
  Himmelblau service namespaces. The host's real file is unchanged.
  Omit this option to use the module default.

  Example:
  ```nix
  osReleaseOverride = ''
    PRETTY_NAME="Ubuntu 22.04.4 LTS"
    NAME="Ubuntu"
    VERSION_ID="22.04"
    VERSION="22.04.4 LTS (Jammy Jellyfish)"
    VERSION_CODENAME=jammy
    ID=ubuntu
    ID_LIKE=debian
  '';
  ```

---

## Flake outputs (reference)

| Output | Description |
|---|---|
| `nixosModules.default` | The full NixOS module; import into any NixOS configuration |
| `overlays.default` | Adds `pkgs.himmelblauTpm.{daemon,broker,sso,pam,nss,aad-tool}` |
| `packages.x86_64-linux.himmelblau-tpm` | TPM-enabled `aad-tool` diagnostic binary |
| `packages.x86_64-linux.himmelblau-tpm-{daemon,broker,sso,pam,nss}` | Individual workspace binaries |
| `checks.x86_64-linux.eval-bare-metal` | Nix eval of `examples/bare-metal-host/` |
| `checks.x86_64-linux.eval-disabled` | Asserts module is a no-op when `enable = false` |
| `checks.x86_64-linux.eval-intune-off` | Asserts compliance shims do not fire when `intuneCompliance.enable = false` |
| `checks.x86_64-linux.eval-intune-on` | Asserts compliance shims emit the OS-release and DMI namespace binds, including custom `osReleaseOverride` text |
| `checks.x86_64-linux.himmelblau-tpm-drv` | Asserts the TPM-enabled derivation evaluates (no build) |
| `checks.aarch64-linux.eval-disabled` | Module eval on aarch64 (package build not supported) |
