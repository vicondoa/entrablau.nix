#!/usr/bin/env bash
# Structural workflow-policy guard for entrablau.nix.
#
# Fails if any workflow in .github/workflows/ violates the hardened
# public-PR posture:
#   1. Unpinned action references (must be full 40-hex-char SHA)
#   2. Permissions elevated beyond `contents: read`
#   3. `pull_request_target` event trigger
#   4. Secrets expansion (`${{ secrets.* }}`) in any workflow
#   5. Automatic self-hosted runner declarations
#
# Exit code: 0 = all clear, 1 = at least one violation found.

set -euo pipefail

WORKFLOW_DIR="${1:-.github/workflows}"
VIOLATIONS=0

# ── helpers ────────────────────────────────────────────────────────────────

fail() {
  echo "FAIL [$1] $2" >&2
  VIOLATIONS=$(( VIOLATIONS + 1 ))
}

info() { echo "INFO $*"; }

# ── 1. Collect workflow files ───────────────────────────────────────────────

mapfile -t WORKFLOWS < <(find "$WORKFLOW_DIR" -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | sort)

if [[ ${#WORKFLOWS[@]} -eq 0 ]]; then
  info "No workflow files found in $WORKFLOW_DIR — nothing to check."
  exit 0
fi

info "Checking ${#WORKFLOWS[@]} workflow(s) in $WORKFLOW_DIR"

for WF in "${WORKFLOWS[@]}"; do
  WF_NAME="$(basename "$WF")"
  info "  → $WF_NAME"

  # ── 1a. Unpinned action references ──────────────────────────────────────
  # Valid pinned form: uses: owner/repo@<exactly 40 lowercase hex chars>
  # (optionally followed by a comment with the human tag).
  # Exclude: local actions (uses: ./) and Docker references (uses: docker://).
  # Match both indented forms: "- uses:" and "  uses:" (step-level key).
  while IFS= read -r line; do
    # strip leading whitespace, optional "- ", then "uses:"
    ref="${line#*uses:}"
    ref="${ref#"${ref%%[! ]*}"}"  # ltrim
    # skip local and docker refs
    [[ "$ref" == ./* ]]       && continue
    [[ "$ref" == docker://* ]] && continue
    # extract the part after @
    after_at="${ref##*@}"
    # strip any trailing comment (everything from # onward)
    sha="${after_at%%#*}"
    sha="${sha%"${sha##*[! ]}"}"  # rtrim whitespace
    if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      fail "$WF_NAME" "Unpinned action: $ref"
    fi
  done < <(grep -v '^\s*#' "$WF" | grep -E 'uses:\s+\S')

  # ── 1b. Elevated permissions ─────────────────────────────────────────────
  # Flag any `write` or `write-all` or `admin` permission value.
  # The only accepted top-level statement is `permissions: contents: read`
  # (or equivalently `contents: read` under a permissions block).
  # Flag: write-all, write (as a permission value), admin.
  if grep -qE '^\s*permissions:\s*write-all' "$WF"; then
    fail "$WF_NAME" "permissions: write-all detected"
  fi
  # Catch job-level or inline permission grants of write/admin
  if grep -qE '^\s+(contents|issues|pull-requests|packages|deployments|id-token|actions|checks|security-events|statuses|pages|repository-projects):\s*(write|admin)' "$WF"; then
    fail "$WF_NAME" "Elevated write/admin permission detected"
  fi

  # ── 1c. pull_request_target ──────────────────────────────────────────────
  # Strip comment lines before checking to avoid false positives from
  # documentation comments that mention the forbidden trigger.
  if grep -v '^\s*#' "$WF" | grep -qF 'pull_request_target'; then
    fail "$WF_NAME" "pull_request_target trigger is forbidden"
  fi

  # ── 1d. Secrets in any workflow ──────────────────────────────────────────
  # In a public-PR posture, secrets must not be referenced in workflows
  # triggered by pull_request (or at all, since that risks exposure).
  if grep -v '^\s*#' "$WF" | grep -qE '\$\{\{\s*secrets\.'; then
    fail "$WF_NAME" "secrets expansion detected — forbidden in public-PR workflows"
  fi

  # ── 1e. Self-hosted runners ──────────────────────────────────────────────
  # Automatic self-hosted runners open privilege-escalation risk.
  # Allowed form: github-hosted runners only (ubuntu-latest, macos-*, etc.).
  if grep -qE "runs-on:.*self-hosted" "$WF"; then
    fail "$WF_NAME" "self-hosted runner declaration detected"
  fi
done

# ── Summary ────────────────────────────────────────────────────────────────

if [[ $VIOLATIONS -gt 0 ]]; then
  echo ""
  echo "FAIL: $VIOLATIONS workflow policy violation(s) found." >&2
  exit 1
else
  echo ""
  echo "OK: All workflow policy checks passed."
fi
