# nixos-entra-id

> ⚠️ **Alpha — v0.1.0 not yet released.** Skeleton repo; implementation
> arrives via the [vicondoa/nixling] refactor's Phase 3.

A **framework-agnostic** NixOS module bundle for authenticating against
Microsoft Entra ID (formerly Azure AD) via [Himmelblau], with Intune
device-compliance shimming.

## What this is

- A self-contained NixOS module you can `imports = [ inputs.nixos-entra-id.nixosModules.default ];`
  in any NixOS configuration:
  - Bare-metal NixOS host (with the usual Lanzaboote + TPM2 caveats)
  - Inside a [nixling]-managed microVM (the primary use case)
  - Inside any other VM framework — it does not depend on nixling
- The Himmelblau workspace (PAM, NSS, broker, daemon) glued to NixOS
  service definitions.
- Optional Intune-compliance helpers: fake DMI, fake `/etc/os-release`,
  systemd `FileDescriptorStoreMax` shimming, sandbox overrides.
- A rebuilt Himmelblau package with the `tpm` cargo feature enabled
  (vendored from the upstream until accepted there).

## What this is NOT

- **Not a security boundary.** Tooling that satisfies Intune
  compliance is, by design, fingerprintable as that tooling. This is
  a *compatibility* layer, not anti-detection.
- **Not officially endorsed by Microsoft, Himmelblau, or Microsoft
  Entra.** Best-effort community implementation.

## License

[Apache-2.0](./LICENSE).

[vicondoa/nixling]: https://github.com/vicondoa/nixling
[Himmelblau]: https://github.com/himmelblau-idm/himmelblau
[nixling]: https://github.com/vicondoa/nixling
