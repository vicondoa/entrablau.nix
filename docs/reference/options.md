# Option reference — nixosEntraId.*

This document covers the full `nixosEntraId.*` option tree as of
v1.0.0 and the migration table from v0.1.0.

## Migration table: v0.1.0 → v1.0.0

| Old option (v0.1.0) | New option (v1.0.0) | Action required |
|---|---|---|
| legacy DMI attribute under `intuneCompliance` | `intuneCompliance.dmiOverride` | Rename the attribute in your configuration. No alias exists. |
| _(absent)_ | `intuneCompliance.osReleaseOverride` | Optional. Set to override `/etc/os-release` fields in the Himmelblau service namespace. |
| legacy repository input | `inputs.entrablau` | Update your flake input name and URL. |
| legacy repository URL | `github:vicondoa/entrablau.nix/v1.0.0` | Update the flake URL. |

There are no compatibility aliases. Configurations using the old
option names will fail to evaluate after upgrading to v1.0.0.

## Top-level options

### `nixosEntraId.enable`

- **Type:** `bool`
- **Default:** `false`
- **Description:** Enable the entrablau.nix module. When `false`, all
  sub-options are ignored and no services, PAM entries, or NSS
  configuration is activated.

### `nixosEntraId.domain`

- **Type:** `list of string`
- **Default:** `[]`
- **Description:** One or more Entra tenant domain names (e.g.,
  `[ "contoso.com" ]`). Passed to the Himmelblau configuration.

### `nixosEntraId.joinType`

- **Type:** `enum [ "join" "register" ]`
- **Default:** `"join"`
- **Example:** `"register"`
- **Description:** `"join"` for Intune-enrolled (Azure AD joined)
  devices. `"register"` for BYOD (Azure AD registered) devices.

### `nixosEntraId.localUser`

- **Type:** `string`
- **Default:** `""`
- **Description:** The local NixOS user name that is the primary Entra
  user on this host. Used by `aad-tool` and the enrolment flow.

### `nixosEntraId.userMap`

- **Type:** `attrsOf string`
- **Default:** `{}`
- **Example:** `{ alice = "alice@contoso.com"; }`
- **Description:** Maps local NixOS user names to Entra UPNs. Rendered
  to `/etc/himmelblau/user-map`.

---

## `nixosEntraId.intuneCompliance`

### `nixosEntraId.intuneCompliance.enable`

- **Type:** `bool`
- **Default:** `true`
- **Description:** Enable the Intune compliance shimming (DMI/OS-release
  bind-mounts, sandbox relaxations). Set to `false` for BYOD /
  Azure-AD-Registered hosts that are not Intune-enrolled.

### `nixosEntraId.intuneCompliance.dmiOverride`

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

### `nixosEntraId.intuneCompliance.osReleaseOverride`

**New in v1.0.0.**

- **Type:** `attrsOf string`
- **Default:** `{}`
- **Description:** `/etc/os-release` field overrides bind-mounted into
  the Himmelblau service namespaces. Keys are os-release field names
  (e.g., `ID`, `VERSION_ID`, `NAME`). Values replace the NixOS
  defaults only inside the Himmelblau service mount namespaces.

  Example:
  ```nix
  osReleaseOverride = {
    ID         = "ubuntu";
    VERSION_ID = "22.04";
  };
  ```

  The host's real `/etc/os-release` is unchanged.

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
| `checks.x86_64-linux.himmelblau-tpm-drv` | Asserts the TPM-enabled derivation evaluates (no build) |
| `checks.aarch64-linux.eval-disabled` | Module eval on aarch64 (package build not supported) |
