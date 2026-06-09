# Agent and contributor workflow — entrablau.nix

This document describes the repository layout, validation commands,
branching and PR workflow, and policies that apply to all contributors
and automated agents working in this repository.

## Repository layout

```
entrablau.nix/
├── flake.nix                  <- top-level flake: inputs, outputs, checks
├── flake.lock                 <- pinned input revisions
├── nixos-modules/
│   ├── default.nix            <- nixosEntraId.* option schema + sub-imports
│   ├── himmelblau.nix         <- PAM/NSS/broker/daemon, user-map, Firefox SSO
│   └── intune-compliance.nix  <- DMI/os-release bind-mounts, sandbox overrides
├── pkgs/
│   └── himmelblau-tpm/        <- TPM-enabled Himmelblau rebuild + crate patches
├── examples/
│   └── bare-metal-host/       <- eval-tested NixOS host example
├── docs/
│   ├── explanation/design.md
│   ├── reference/options.md
│   ├── reference/github-actions.md
│   └── how-to/import-into-nixos.md
├── README.md
├── AGENTS.md                  <- this file
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── THIRD-PARTY.md
└── LICENSE                    <- Apache-2.0
```

## Code-is-canon policy

The flake itself is the authoritative source of truth. Documentation
describes what the code does; if there is a discrepancy, update the
documentation, not the code (unless the code is wrong). Documentation
changes do not require a separate tracking ticket; they land in the
same PR as the code they describe.

## Validation commands

Run these before opening a PR and after merging to confirm nothing is
broken. All commands run from the repository root.

```bash
# Evaluate all flake checks (no Rust compile — just Nix evaluation)
nix flake check --no-build

# Build the TPM-enabled aad-tool (full Rust compile; ~10 min cold)
nix build .#himmelblau-tpm

# Evaluate the bare-metal-host example
nix eval ./examples/bare-metal-host#nixosConfigurations.bare-metal-host.config.system.build.toplevel.drvPath

# Quick content checks (no old repo names, no old option names,
# no framework-specific references in docs)
rg --type md 'nixos-entra-id' docs/ README.md CHANGELOG.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD-PARTY.md
rg --type md 'fakeDmi' docs/ README.md CHANGELOG.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD-PARTY.md
rg --type md 'nixling' docs/ README.md CHANGELOG.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD-PARTY.md
```

Expected output for the `rg` checks: no matches (exit code 1 from rg).

## Branch and PR workflow

1. **Branch naming:** `agent/<topic>` for agent-driven branches;
   `feat/<topic>`, `fix/<topic>`, `docs/<topic>` for human branches.
2. **One logical change per PR.** Large agent tasks may span multiple
   commits but must be squashed before merge (see below).
3. **Squash on merge.** All PRs are squash-merged. The squash commit
   message must be a concise imperative-mood summary. Multi-line body
   is permitted for context.
4. **No force-push to `main` or `release/*` branches.** Feature and
   agent branches may be rebased freely.
5. **PR description** must list: what changed, why, and any
   integration notes for sibling agents (CI, Module/API, etc.).

## Panel review gate

PRs that touch the public option namespace (`nixosEntraId.*`),
`flake.nix`, or `pkgs/himmelblau-tpm/` require at least one human
reviewer to approve before merge. Documentation-only PRs (changes
confined to `docs/`, `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`,
`SECURITY.md`, `AGENTS.md`, `THIRD-PARTY.md`) may be merged by the
maintainer without a second reviewer.

## GitHub Actions security policy

See [`docs/reference/github-actions.md`](./docs/reference/github-actions.md)
for the full CI and security posture. Key points:

- All workflows run on GitHub-hosted runners; no self-hosted runners.
- Third-party actions are pinned to full commit SHAs.
- The `GITHUB_TOKEN` is granted minimum required permissions per job.
- `pull_request_target` is not used.
- Secret scanning and dependency review are enabled at the repository
  level.

## Naming and option-migration policy

- The public option root is `nixosEntraId.*` and is stable from v1.0.0.
- When an option is renamed, the old name is **removed without an alias**
  in the next major version. Aliases are never added; callers must
  migrate.
- Renaming an option requires a CHANGELOG entry in the current release
  section and a row in the migration table in
  [`docs/reference/options.md`](./docs/reference/options.md).
- New options default to `null` or a safe no-op value so existing
  configurations continue to evaluate without change.

## Scope boundaries for agents

| Agent branch | Owned paths |
|---|---|
| `agent/docs` | `README.md`, `CHANGELOG.md`, `THIRD-PARTY.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/**`, deletion of `examples/inside-nixling-vm/**` |
| `agent/module-api` | `nixos-modules/**`, `pkgs/**`, `flake.nix`, `examples/bare-metal-host/**` |
| `agent/ci-security` | `.github/**`, guard scripts |

Agents must not edit paths outside their owned scope. If a cross-scope
change is needed, leave an integration note in the PR description for
the owning agent.
