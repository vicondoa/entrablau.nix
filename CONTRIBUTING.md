# Contributing to entrablau.nix

Thank you for your interest in contributing. This is a small
community-maintained flake; please read these guidelines before
opening an issue or PR.

## Before you start

- Check the [open issues](https://github.com/vicondoa/entrablau.nix/issues)
  to see if your change is already tracked.
- For significant changes (new options, breaking changes, large
  refactors), open an issue first to discuss the approach.
- For documentation fixes, typos, or clarifications, a PR is welcome
  directly without a prior issue.

## What to contribute

- Bug fixes with a clear reproduction case.
- Documentation improvements (options, how-tos, examples).
- Dependency updates with a rationale and verification that the
  existing checks still pass.
- New options following the naming conventions in `AGENTS.md`.

## What not to contribute

- Framework-specific examples or integration guides (e.g., for any
  named VM framework). This repo is framework-agnostic.
- Options that expose host-specific values in the module API. Host
  configuration belongs in the consumer's flake.
- Changes to `.github/` workflow files (those are owned by the CI
  branch; see `AGENTS.md`).

## Development environment

You need Nix with flakes enabled:

```bash
# Install Nix (if not already installed)
# https://nixos.org/download

# Enable flakes (add to ~/.config/nix/nix.conf or /etc/nix/nix.conf)
experimental-features = nix-command flakes
```

## Validation

Run all checks before submitting a PR:

```bash
# Nix evaluation checks (fast — no Rust compile)
nix flake check --no-build

# Full package build (slow first time; Rust compile)
nix build .#himmelblau-tpm

# Docs content checks (no stale references)
rg --type md 'nixos-entra-id|fakeDmi' docs/ README.md CHANGELOG.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD-PARTY.md
```

## PR conventions

- Squash commits before asking for review (or enable squash-merge in
  the PR).
- PR title: imperative mood, 60 characters or fewer.
- PR description: what changed, why, and any integration notes.
- Include a `Co-authored-by` trailer if the commit was written with
  AI assistance.

## Option migration policy

See `AGENTS.md` — Naming and option-migration policy. In short: no
compatibility aliases; callers must migrate to the new name.

## Code style

This project uses standard Nix formatting conventions. There is no
enforced formatter at this time; match the style of the surrounding
code.

## License

By submitting a PR you agree that your contribution is licensed under
Apache-2.0, consistent with the repository's [`LICENSE`](./LICENSE).
Contributions to `pkgs/himmelblau-tpm/` that become part of the built
outputs are additionally subject to GPL-3.0-or-later (see
[`THIRD-PARTY.md`](./THIRD-PARTY.md)).
