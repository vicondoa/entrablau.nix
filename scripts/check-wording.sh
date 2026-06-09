#!/usr/bin/env bash
# Leak-free wording / reference guard for entrablau.nix.
#
# Scans committed surfaces for:
#   A) Old repository identifier (should be replaced with the new name)
#   B) Legacy DMI option spelling (should not appear in docs/modules)
#   C) Forbidden framework-coupling reference — constructed at runtime
#      from split strings so this file does not store the literal.
#   D) Forbidden host-local path reference — constructed at runtime
#      from split strings so this file does not store the literal.
#
# DESIGN NOTE: patterns C and D are assembled from variable parts below
# and never appear verbatim in this source file. This prevents the guard
# from being a source of leakage and means it does not need to exclude
# itself from scanning.
#
# Exit code: 0 = clean, 1 = violations found.

set -euo pipefail

# ── Runtime pattern construction ────────────────────────────────────────────
#
# C) Forbidden framework-coupling name: assembled from two parts.
#    Each variable holds a non-matching fragment; only the concatenated
#    result is the forbidden string.
_FC_A="nix"
_FC_B="ling"
PAT_FRAMEWORK="${_FC_A}${_FC_B}"

# D) Forbidden host-local NixOS config directory path: assembled from parts.
_HL_A="/etc/"
_HL_B="nix"
_HL_C="os"
PAT_HOST_LOCAL="${_HL_A}${_HL_B}${_HL_C}"

# A) Old repository identifier: assembled to avoid trivial grep matches
#    against this file's own source.
_OR_A="nixos-"
_OR_B="entra-id"
PAT_OLD_REPO="${_OR_A}${_OR_B}"

# B) Legacy DMI option spelling: assembled from parts so this guard does
#    not store the spelling verbatim.
_DO_A="fake"
_DO_B="Dmi"
PAT_LEGACY_DMI="${_DO_A}${_DO_B}"

# ── Scope ───────────────────────────────────────────────────────────────────
# Scan all text files that are committed surfaces (docs, modules, examples,
# workflows, scripts, tests). Exclude the .git directory and binary files.

# Collect files via git-tracked list (most accurate for "committed surfaces").
# Fall back to find if not in a git repo.
if git rev-parse --is-inside-work-tree &>/dev/null; then
  mapfile -t FILES < <(git ls-files \
    -- \
    '*.md' '*.nix' '*.lock' '*.yml' '*.yaml' '*.sh' '*.txt' \
    'README*' 'CHANGELOG*' 'THIRD-PARTY*' 'AGENTS*' \
    'CONTRIBUTING*' 'SECURITY*' \
    2>/dev/null | sort)
else
  mapfile -t FILES < <(find . \
    -not -path './.git/*' \
    \( -name '*.md' -o -name '*.nix' -o -name '*.yml' -o -name '*.yaml' \
       -o -name '*.sh' -o -name '*.txt' -o -name '*.lock' \
       -o -name 'README*' -o -name 'CHANGELOG*' -o -name 'THIRD-PARTY*' \
       -o -name 'AGENTS*' -o -name 'CONTRIBUTING*' -o -name 'SECURITY*' \
    \) -type f | sort)
fi

# ── Scanning ─────────────────────────────────────────────────────────────────

VIOLATIONS=0
declare -A VIOLATION_COUNTS=(
  [old_repo]=0
  [legacy_dmi]=0
  [framework]=0
  [host_local]=0
)

scan_pattern() {
  local key="$1" pat="$2" file="$3" label="$4"
  local matches
  matches=$(grep -nF -- "$pat" "$file" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "FAIL [$label] $file" >&2
    while IFS= read -r m; do
      echo "  $m" >&2
    done <<< "$matches"
    VIOLATIONS=$(( VIOLATIONS + 1 ))
    VIOLATION_COUNTS[$key]=$(( VIOLATION_COUNTS[$key] + 1 ))
  fi
}

echo "Scanning ${#FILES[@]} file(s) for wording/reference violations…"
echo ""

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  # Skip binary files
  if ! file "$f" | grep -qE 'text|empty|ASCII|UTF'; then
    continue
  fi

  scan_pattern "old_repo"   "$PAT_OLD_REPO"   "$f" "old-repo-name"
  scan_pattern "legacy_dmi" "$PAT_LEGACY_DMI" "$f" "legacy-dmi-option"
  scan_pattern "framework"  "$PAT_FRAMEWORK"  "$f" "framework-coupling"
  scan_pattern "host_local" "$PAT_HOST_LOCAL" "$f" "host-local-path"
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Results:"
echo "  old repo name occurrences (files):    ${VIOLATION_COUNTS[old_repo]}"
echo "  legacy DMI option occurrences (files): ${VIOLATION_COUNTS[legacy_dmi]}"
echo "  framework-coupling occurrences (files): ${VIOLATION_COUNTS[framework]}"
echo "  host-local path occurrences (files):   ${VIOLATION_COUNTS[host_local]}"
echo ""

if [[ $VIOLATIONS -gt 0 ]]; then
  echo "FAIL: $VIOLATIONS file(s) contain wording/reference violations." >&2
  echo "NOTE: Violations in docs/modules/examples outside agent/ci-security scope" >&2
  echo "      are expected until the docs and module-api branches are integrated." >&2
  exit 1
else
  echo "OK: No wording/reference violations found."
fi
