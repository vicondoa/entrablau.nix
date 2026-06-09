# GitHub Actions — CI and security posture

## Workflow structure

### `ci.yml` — main check workflow

Triggered on: `push` to `main`; `pull_request` (all targets).

Single job — `check` — runs on `ubuntu-latest`:

| Step | Command | Purpose |
|---|---|---|
| Checkout | `actions/checkout` (SHA-pinned) | Fetch the repository |
| Install Nix | `cachix/install-nix-action` (SHA-pinned) | Bootstrap Nix with flakes enabled |
| Guard self-tests | `bash tests/test-guards.sh` | Validate that the CI guard scripts themselves behave correctly |
| Workflow policy guard | `bash scripts/check-workflow-policy.sh` | Enforce SHA-pinning, no secrets, no self-hosted runners, no `pull_request_target` — for both workflow files and composite actions under `.github/actions/` |
| Wording guard | `bash scripts/check-wording.sh` | Ensure no stale repo-name, option-name, or framework references in committed surfaces |
| Nix flake check | `nix flake check --all-systems` | Full evaluation and build check across all supported systems |

## Security policies

### Runner security

- All jobs run on `ubuntu-latest` GitHub-hosted runners.
- No self-hosted runners. Self-hosted runners expose the host to
  arbitrary code from PRs and are not used here.

### Action pinning

All third-party GitHub Actions — including steps inside composite actions
under `.github/actions/` — must be pinned to a full commit SHA, not a
mutable tag. Example:

```yaml
# Correct — pinned to SHA
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

# Wrong — mutable tag
uses: actions/checkout@v4
```

The `ci.yml` workflow policy guard (`scripts/check-workflow-policy.sh`)
enforces SHA pinning at CI time for both workflow files and any composite
actions under `.github/actions/`.

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

## Guards

CI runs the guard self-tests, workflow-policy guard, and wording guard
in every check run:

```bash
bash tests/test-guards.sh
bash scripts/check-workflow-policy.sh
bash scripts/check-wording.sh
```

The wording guard constructs restricted patterns at runtime so the guard
itself does not commit those terms. Any match in committed surfaces fails CI.

The workflow-policy guard scans both `.github/workflows/*.yml` and
composite/local actions under `.github/actions/**/action.yml`.

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
