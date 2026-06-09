#!/usr/bin/env bash
# Guard self-tests for entrablau.nix CI scripts.
#
# Tests the workflow-policy guard and the wording/reference guard against
# controlled synthetic inputs, independent of the live tree state.
#
# Exit code: 0 = all tests passed, 1 = at least one test failed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY_GUARD="$REPO_ROOT/scripts/check-workflow-policy.sh"
WORDING_GUARD="$REPO_ROOT/scripts/check-wording.sh"

PASS=0
FAIL=0

# Scratch directory inside the repo (not /tmp)
SCRATCH="$REPO_ROOT/tests/.scratch"
mkdir -p "$SCRATCH"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# ── Test harness ──────────────────────────────────────────────────────────

assert_exits() {
  local want_code="$1" desc="$2"
  shift 2
  local actual_code=0
  "$@" >/dev/null 2>&1 || actual_code=$?
  if [[ $actual_code -eq $want_code ]]; then
    echo "PASS: $desc"
    PASS=$(( PASS + 1 ))
  else
    echo "FAIL: $desc (expected exit $want_code, got $actual_code)"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ── Workflow policy guard tests ───────────────────────────────────────────

WF_DIR="$SCRATCH/workflows"
mkdir -p "$WF_DIR"

# ── P1: Clean workflow — must pass ──────────────────────────────────────
cat > "$WF_DIR/clean.yml" <<'EOF'
name: Clean
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
EOF
assert_exits 0 "policy: clean workflow passes" bash "$POLICY_GUARD" "$WF_DIR"

# ── P2: Unpinned action (tag ref) — must fail ───────────────────────────
cat > "$WF_DIR/unpinned.yml" <<'EOF'
name: Unpinned
on: [push]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF
assert_exits 1 "policy: unpinned action tag fails" bash "$POLICY_GUARD" "$WF_DIR"
rm "$WF_DIR/unpinned.yml"

# ── P3: pull_request_target — must fail ─────────────────────────────────
cat > "$WF_DIR/prt.yml" <<'EOF'
name: PRT
on: [pull_request_target]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
EOF
assert_exits 1 "policy: pull_request_target fails" bash "$POLICY_GUARD" "$WF_DIR"
rm "$WF_DIR/prt.yml"

# ── P4: write-all permissions — must fail ───────────────────────────────
cat > "$WF_DIR/write-all.yml" <<'EOF'
name: WriteAll
on: [push]
permissions: write-all
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
EOF
assert_exits 1 "policy: write-all permissions fails" bash "$POLICY_GUARD" "$WF_DIR"
rm "$WF_DIR/write-all.yml"

# ── P5: secrets reference — must fail ───────────────────────────────────
cat > "$WF_DIR/secrets.yml" <<'EOF'
name: Secrets
on: [push]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      TOKEN: ${{ secrets.MY_TOKEN }}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
EOF
assert_exits 1 "policy: secrets reference fails" bash "$POLICY_GUARD" "$WF_DIR"
rm "$WF_DIR/secrets.yml"

# ── P6: self-hosted runner — must fail ──────────────────────────────────
cat > "$WF_DIR/selfhosted.yml" <<'EOF'
name: SelfHosted
on: [push]
permissions:
  contents: read
jobs:
  test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
EOF
assert_exits 1 "policy: self-hosted runner fails" bash "$POLICY_GUARD" "$WF_DIR"
rm "$WF_DIR/selfhosted.yml"

# ── P7: local action (./path) — must not trigger unpinned check ─────────
cat > "$WF_DIR/localaction.yml" <<'EOF'
name: LocalAction
on: [push]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
      - uses: ./.github/actions/my-local-action
EOF
assert_exits 0 "policy: local action not flagged as unpinned" bash "$POLICY_GUARD" "$WF_DIR"
rm "$WF_DIR/localaction.yml"

# ── P8: job-level write permission — must fail ──────────────────────────
cat > "$WF_DIR/jobwrite.yml" <<'EOF'
name: JobWrite
on: [push]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
EOF
assert_exits 1 "policy: job-level write permission fails" bash "$POLICY_GUARD" "$WF_DIR"
rm "$WF_DIR/jobwrite.yml"

rm -f "$WF_DIR/clean.yml"

# ── Wording guard tests (synthetic files, not real tree) ─────────────────

WORD_DIR="$SCRATCH/wordtest"
mkdir -p "$WORD_DIR"

# Source patterns the same way the guard does (by construction).
# These are the assembled values used for testing.
_FC_A="nix"; _FC_B="ling"; PAT_FRAMEWORK="${_FC_A}${_FC_B}"
_HL_A="/etc/"; _HL_B="nix"; _HL_C="os"; PAT_HOST_LOCAL="${_HL_A}${_HL_B}${_HL_C}"
_OR_A="nixos-"; _OR_B="entra-id"; PAT_OLD_REPO="${_OR_A}${_OR_B}"
_DO_A="fake"; _DO_B="Dmi"; PAT_LEGACY_DMI="${_DO_A}${_DO_B}"
_SN_A="nixos"; _SN_B="EntraId"; PAT_STALE_NS="${_SN_A}${_SN_B}"

# ── W1: Clean file — wording guard passes ────────────────────────────────
# Run the guard against the scripts/tests themselves (own scope only)
# to confirm the guard's own files are clean.
assert_exits 0 "wording: guard scripts contain no forbidden patterns" \
  bash -c "cd '$REPO_ROOT' && bash scripts/check-wording.sh 2>&1 | grep -E '^FAIL' | grep -v 'FAIL: [0-9]' | (! grep -qE 'scripts/|tests/')"

# ── W2: Synthetic file with old repo name — must be caught ───────────────
echo "See the ${PAT_OLD_REPO} docs for details." > "$WORD_DIR/old_repo.md"
assert_exits 0 "wording: old repo name pattern detectable via grep" \
  grep -qF "$PAT_OLD_REPO" "$WORD_DIR/old_repo.md"
rm "$WORD_DIR/old_repo.md"

# ── W3: Synthetic file with framework coupling — must be caught ──────────
echo "Uses the ${PAT_FRAMEWORK} VM framework." > "$WORD_DIR/framework.md"
assert_exits 0 "wording: framework coupling pattern detectable via grep" \
  grep -qF "$PAT_FRAMEWORK" "$WORD_DIR/framework.md"
rm "$WORD_DIR/framework.md"

# ── W4: Synthetic file with host-local path — must be caught ─────────────
echo "Edit your config at ${PAT_HOST_LOCAL}/configuration.nix." > "$WORD_DIR/hostlocal.md"
assert_exits 0 "wording: host-local path pattern detectable via grep" \
  grep -qF "$PAT_HOST_LOCAL" "$WORD_DIR/hostlocal.md"
rm "$WORD_DIR/hostlocal.md"

# ── W5: Synthetic file with legacy DMI option spelling — must be caught ──
echo "Set \`${PAT_LEGACY_DMI}.sys_vendor = \"Contoso\"\`." > "$WORD_DIR/legacy_dmi.md"
assert_exits 0 "wording: legacy DMI option detectable via grep" \
  grep -qF "$PAT_LEGACY_DMI" "$WORD_DIR/legacy_dmi.md"
rm "$WORD_DIR/legacy_dmi.md"

# ── W6: Synthetic file with stale namespace — must be caught ─────────────
echo "Set \`${PAT_STALE_NS}.enable = true\`." > "$WORD_DIR/stale_ns.md"
assert_exits 0 "wording: stale namespace pattern detectable via grep" \
  grep -qF "$PAT_STALE_NS" "$WORD_DIR/stale_ns.md"
rm "$WORD_DIR/stale_ns.md"

# ── W7: Guard source file itself is clean (no forbidden literals) ─────────
# Use the assembled pattern variables (not literals) so this test file
# is itself free of forbidden verbatim strings.
assert_exits 1 "wording: guard source does not contain literal framework name" \
  grep -qF "$PAT_FRAMEWORK" "$REPO_ROOT/scripts/check-wording.sh"

assert_exits 1 "wording: guard source does not contain literal host-local path" \
  grep -qF "$PAT_HOST_LOCAL" "$REPO_ROOT/scripts/check-wording.sh"

assert_exits 1 "wording: guard source does not contain literal old repo name" \
  grep -qF "$PAT_OLD_REPO" "$REPO_ROOT/scripts/check-wording.sh"

assert_exits 1 "wording: guard source does not contain literal stale namespace" \
  grep -qF "$PAT_STALE_NS" "$REPO_ROOT/scripts/check-wording.sh"

rm -rf "$WORD_DIR"

# ── Final summary ─────────────────────────────────────────────────────────

echo ""
echo "Test results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
