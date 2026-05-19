# `pkgs/himmelblau-tpm/` — update process

This package rebuilds Himmelblau (Microsoft Entra ID daemon) from a
specific git rev with three layered patches:

1. **flake input pin** (`inputs.himmelblau`) — pulled in by
   `flake.nix`, currently rev `b3c48849`. Provides the workspace's
   pre-generated `Cargo.nix` (crate2nix output).
2. **Cargo.nix surgery (sed)** — turns on the `tpm` cargo feature on
   the `himmelblau_unix_common`, `kanidm-hsm-crypto`, and
   `libhimmelblau` dep entries inside every workspace binary
   (aad-tool / daemon / pam / broker / nss). Without this the TPM
   crates compile but the binaries report
   `"Hardware TPM supported was not enabled in this build."`
3. **Two vendored crates with sed patches** to fix real bugs that
   block Intune device enrolment:
   - **`libhimmelblau-0.8.18`** — PEM-wraps the enrolment CSR with
     RFC 7468 64-char line chunking. Intune's strict tenants reject
     the upstream raw-base64-of-DER form.
   - **`kanidm-hsm-crypto-0.3.6`** — adds X.509v3 `KeyUsage`
     (critical: digitalSignature, keyEncipherment) and
     `ExtendedKeyUsage` (clientAuth) extensions to the TPM-generated
     CSR. Without these Intune rejects with a misleading
     "must be PEM-encoded" error.

Each patch is verified at build time with a `grep` guard — if a future
upstream changes the surrounding source enough that the sed pattern
stops matching, the build fails loudly inside the `runCommand` rather
than mysteriously at runtime.

## Bumping the himmelblau flake input

```
cd /path/to/nixos-entra-id
nix flake lock --update-input himmelblau
nix build .#himmelblau-tpm
```

Things to check after the build attempts:

- **Did the `Cargo.nix` feature-injection seds still match?** Build
  failures with `error: builder for '...-himmelblau-tpm-source.drv'
  failed` are usually upstream renaming a dep or restructuring
  `Cargo.nix`. Read the failing sed pattern and adapt.
- **Does the new rev still need our libhimmelblau / kanidm-hsm-crypto
  versions?** If upstream bumps either crate, our crateOverrides keep
  pointing at our pinned vendored copies — that's fine for stability
  but you miss upstream improvements. To pick up newer crate
  versions, do a coordinated bump (see below).
- **Test on a throwaway VM clone or non-production host** before
  pushing to production. A broken daemon means re-enrolling, which
  in a corporate tenant means an IT helpdesk ticket. The
  `FileDescriptorStoreMax=1` shim in `intune-compliance.nix` makes
  re-enrolment unnecessary across normal restarts; preserving that
  state across a rebuild is the goal.

## Bumping the vendored crates (`libhimmelblau`, `kanidm-hsm-crypto`)

Both are pinned by `crates.io` URL + `sha256` inside `default.nix`.
To bump:

1. Confirm the upstream issue is **still present** in the new version.
   The PEM-wrap and KeyUsage bugs were both filed upstream (see
   git log for refs); a fix may make our patch redundant.
2. Update the version in the URL and the sha256:
   ```
   nix-prefetch-url --type sha256 \
     https://crates.io/api/v1/crates/libhimmelblau/<NEW>/download
   ```
3. Re-derive each sed pattern against the new source. The patterns
   anchor on specific lines:
   - libhimmelblau: `.map_err(|e| MsalError::CryptoFail(...))?;`
     just after the CSR DER bind, and
     `"CertificateSigningRequest": STANDARD.encode(csr_der),` in
     the `enroll()` payload.
   - kanidm-hsm-crypto: the `use` line in
     `src/provider/mod.rs` that imports from `crypto_glue::x509`,
     and the `let csr_to_sign = req_builder` line just above
     `.finalize()`.
4. Build. The in-derivation `grep` guards will fail fast if a sed
   slipped silently.
5. **Test enrolment end-to-end on a fresh host/VM** before committing:
   `aad-tool enroll` should succeed and the Intune compliance status
   should flip to green within ~30s.

## Bumping the himmelblau-tpm package overall

When in doubt, bump in this order:

1. The two vendored crates (smallest blast radius).
2. The flake input (`inputs.himmelblau`).
3. Re-test `aad-tool tpm` (must report TPM available), then
   `aad-tool enroll`, then Firefox SSO via the linux-entra-sso
   extension, then an interactive Hello PIN auth.

## Sharp edges you will hit

- **`${pkgs.X}` interpolation inside the heredoc** — the `default.nix`
  surgery escapes `$` as `''$` so the literal `${pkgs.X}` string
  lands in the OUTPUT `default.nix` and Nix string context properly
  registers clang / glibc / tpm2-tss as build inputs of the
  crateOverrides. Pre-substituting to literal `/nix/store/...` paths
  breaks the sandbox (bindgen panics
  `"Unable to find libclang ... (invalid: [])"`). The top-of-file
  comment in `default.nix` explains this in detail.
- **Sed delimiter `@`** — used because patterns contain `/` and `|`
  in Rust source. Don't switch to `/` without escaping.
- **`sed -z` is intentional** in the Cargo.nix patches — those
  patterns span multiple lines and need newline-aware multi-line
  matching.
- **Crate2nix vs. cargo features** — upstream's pre-generated
  `Cargo.nix` does not propagate the workspace's `tpm` feature flag
  the way `cargo build --features tpm` would. The sed surgery is the
  shortest path that doesn't require re-running crate2nix.

## Architecture support

This package is currently exposed as `packages.x86_64-linux.*` only.
The upstream Himmelblau Cargo.nix is wired for x86_64-linux, and the
Intune CSR-enrolment path has not been verified on aarch64. Lift the
`himmelblauSystems` gate in `flake.nix` once aarch64 is wanted by a
real consumer and the upstream packaging follows.

## When to delete this package

If/when upstream Himmelblau:
- Ships a release that has `tpm` enabled by default in the daemon
  binaries, AND
- Has merged the PEM CSR fix (libhimmelblau), AND
- Has merged the KeyUsage/ExtendedKeyUsage extensions
  (kanidm-hsm-crypto)

…then this package collapses to just `inputs.himmelblau.packages.<arch>.<bin>`
and can be deleted. The consumer-facing `nixosModules.default` would
switch to passing those packages directly to the upstream
`services.himmelblau` module without an overlay.

