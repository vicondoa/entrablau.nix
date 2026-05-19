# nixos-entra-id

> ⚠️ **Alpha — v0.1.0 not yet released.** Skeleton repo; implementation
> arrives via the [vicondoa/nixling] refactor's Phase 3. **Pre-1.0
> APIs and option names will change without warning** before v0.1.0
> tags.

An **unofficial, framework-agnostic** community NixOS module bundle
for authenticating against Microsoft Entra ID (formerly Azure AD)
via [Himmelblau], with Intune device-compliance shimming.

## Project status

- **Stage:** pre-1.0, alpha — repo is a skeleton; implementation lands
  via the upstream [vicondoa/nixling] refactor's Phase 3
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

- A self-contained NixOS module you can use in any NixOS
  configuration (planned API; not yet implemented):
  ```nix
  # In your flake.nix:
  inputs.nixos-entra-id.url = "github:vicondoa/nixos-entra-id/v0.1.0";

  # In your NixOS / VM config (once v0.1.0 ships):
  imports = [ inputs.nixos-entra-id.nixosModules.default ];
  nixosEntraId.enable = true;
  ```
- Works on:
  - Bare-metal NixOS host (with the usual Lanzaboote + TPM2 caveats)
  - Inside a [nixling]-managed microVM (the primary use case)
  - Inside any other VM framework — it does not depend on nixling
- The Himmelblau workspace (PAM, NSS, broker, daemon) glued to NixOS
  service definitions.
- Optional Intune-compliance helpers: fake DMI, fake `/etc/os-release`,
  systemd `FileDescriptorStoreMax` shimming, sandbox overrides.
- A rebuilt Himmelblau package with the `tpm` cargo feature enabled
  (vendored from upstream until accepted there).

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

[Apache-2.0](./LICENSE).

[vicondoa/nixling]: https://github.com/vicondoa/nixling
[Himmelblau]: https://github.com/himmelblau-idm/himmelblau
[nixling]: https://github.com/vicondoa/nixling
