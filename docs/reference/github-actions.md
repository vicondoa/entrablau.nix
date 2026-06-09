# GitHub Actions — CI and security posture

> **Integration note:** This document describes the *intended* CI and
> security posture for entrablau.nix. The CI/security branch
> (`agent/ci-security`) owns `.github/` and is responsible for the
> actual workflow implementation. Before merging either branch, the
> integrator must reconcile this document with the real workflow files
> to ensure they are consistent. Any discrepancy should be resolved by
> updating this document (if the implementation is correct) or the
> workflows (if the design has changed).

## Intended workflow structure

### `ci.yml` — main check workflow

Triggered on: `push` to `main` and `release/*`; `pull_request` to
`main`.

Jobs:

| Job | Command | Purpose |
|---|---|---|
| `eval-checks` | `nix flake check --no-build` | Fast Nix evaluation of all check outputs; no Rust compile |
| `build-himmelblau-tpm` | `nix build .#himmelblau-tpm` | Full TPM-enabled build; uses Nix cache to avoid cold compiles on repeat runs |
| `lint-docs` | `rg` content checks (see below) | Asserts no stale repo-name, option-name, or framework references in owned docs files |

### `security.yml` — dependency and secret scanning

Triggered on: `push` to `main`; scheduled weekly.

Jobs:

| Job | Tool | Purpose |
|---|---|---|
| `dependency-review` | GitHub Dependency Review Action | Flags new vulnerable dependencies in `flake.lock` updates |
| `secret-scan` | GitHub secret scanning (repository setting) | Blocks accidental credential commits |

## Security policies

### Runner security

- All jobs run on `ubuntu-latest` GitHub-hosted runners.
- No self-hosted runners. Self-hosted runners expose the host to
  arbitrary code from PRs and are not used here.

### Action pinning

All third-party GitHub Actions must be pinned to a full commit SHA,
not a mutable tag. Example:

```yaml
# Correct — pinned to SHA
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

# Wrong — mutable tag
uses: actions/checkout@v4
```

The CI/security branch agent is responsible for maintaining SHA pins
when actions publish new releases.

### Token permissions

The `GITHUB_TOKEN` is granted minimum required permissions per job
using the `permissions:` key. The default permission level for the
repository is `read`. Jobs that need to write (e.g., create a release)
declare `contents: write` explicitly.

### No `pull_request_target`

`pull_request_target` runs with write permissions in the context of the
base branch and is not used. All PR workflows use `pull_request` (read-
only context, fork-safe).

### Caching

Nix store caches may be used via `nix-community/cache-nix-action` or
similar, pinned to a SHA. Cache keys must include the `flake.lock`
hash to avoid stale Himmelblau build artefacts.

## Docs lint checks

The following `rg` checks are run in CI to guard against stale
references in documentation:

```bash
# No old repo name
rg --type md 'nixos-entra-id' \
  docs/ README.md CHANGELOG.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD-PARTY.md

# No old option name
rg --type md 'fakeDmi' \
  docs/ README.md CHANGELOG.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD-PARTY.md

# No named framework references
rg --type md 'nixling' \
  docs/ README.md CHANGELOG.md AGENTS.md CONTRIBUTING.md SECURITY.md THIRD-PARTY.md
```

Each check is expected to return exit code 1 (no matches). A match
fails the job.

## Branch protection

`main` and `release/*` branches require:

- At least one approving review for PRs touching `nixos-modules/**`,
  `pkgs/**`, or `flake.nix` (see `AGENTS.md` — Panel review gate).
- All CI checks passing before merge.
- No force-pushes.

## Secrets and credentials

No secrets are required for the default CI checks. If a binary cache
push token (`NIX_SECRET_KEY` or Cachix token) is added in future,
it must be stored as a GitHub Actions secret and accessed via
`${{ secrets.TOKEN_NAME }}` — never hardcoded in workflow files.
