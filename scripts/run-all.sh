#!/usr/bin/env bash
# run-all.sh - run every scenario under scenarios/*/run.sh and print a summary.
#
# Usage:
#   ./scripts/run-all.sh              # run all scenarios
#   ./scripts/run-all.sh 03 07 12     # run only scenarios whose dir name starts with these
#
# Env:
#   SEMREL_E2E_REBUILD=1   force rebuild of semrel + plugin binaries
#   SEMREL_E2E_WORKDIR     override the scratch dir used for fixture repos (default: .work)

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
E2E_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

FILTERS=("$@")

declare -a PASSED=() FAILED=() SKIPPED=()

matches_filter() {
  local name="$1"
  [[ ${#FILTERS[@]} -eq 0 ]] && return 0
  local f
  for f in "${FILTERS[@]}"; do
    [[ "$name" == "$f"* ]] && return 0
  done
  return 1
}

for dir in "$E2E_ROOT"/scenarios/*/; do
  name="$(basename "$dir")"
  [[ -f "$dir/run.sh" ]] || continue
  matches_filter "$name" || continue

  echo ""
  echo "=== $name ==="
  if bash "$dir/run.sh"; then
    PASSED+=("$name")
  else
    rc=$?
    if [[ $rc -eq 77 ]]; then
      SKIPPED+=("$name")
    else
      FAILED+=("$name")
    fi
  fi
done

echo ""
echo "================ Summary ================"
echo "Passed:  ${#PASSED[@]}"
for n in "${PASSED[@]:-}"; do [[ -n "$n" ]] && echo "  [PASS] $n"; done
echo "Skipped: ${#SKIPPED[@]}"
for n in "${SKIPPED[@]:-}"; do [[ -n "$n" ]] && echo "  [SKIP] $n"; done
echo "Failed:  ${#FAILED[@]}"
for n in "${FAILED[@]:-}"; do [[ -n "$n" ]] && echo "  [FAIL] $n"; done
echo "==========================================="

[[ ${#FAILED[@]} -eq 0 ]]
