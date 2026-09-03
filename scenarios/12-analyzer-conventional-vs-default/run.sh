#!/usr/bin/env bash
# Category coverage: analyzer (conventional, default).
# Neither analyzer plugin is currently wired into the semrel release
# pipeline -- semrel's core bump logic uses the `rules:` config block
# directly, and grepping semrel/internal/cli for "analyzer" turns up
# nothing. Their README documents SEMREL_PLUGIN_* config and SEMREL_BUMP as
# output, but not how commit history reaches them, so this is a best-effort
# smoke test: invoke each binary for real inside a repo with a breaking-
# change commit and record what it does. Update this scenario once semrel
# core documents/wires an analyzer phase -- a non-zero exit here may be a
# real plugin bug, or may just mean the invocation contract guessed below
# is wrong; check the plugin's own repo before assuming the former.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

CONV=$(build_plugin analyzer-conventional analyzer-conventional)
DEFAULT=$(build_plugin analyzer-default analyzer-default)

REPO=$(new_scenario_repo "12-analyzer-conventional-vs-default")
echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat!: breaking change to the public API"

run_analyzer() {
  local label="$1" bin="$2"
  local out rc
  set +e
  out="$(cd "$REPO" && SEMREL_TAG_PREFIX="v" "$bin" 2>&1)"
  rc=$?
  set -e
  echo "  [INFO] $label exit=$rc output=$(echo "$out" | tr '\n' ' ' | cut -c1-200)"
}

run_analyzer "analyzer-conventional" "$CONV"
run_analyzer "analyzer-default" "$DEFAULT"

finish
