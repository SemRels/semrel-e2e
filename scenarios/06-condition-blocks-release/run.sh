#!/usr/bin/env bash
# Category coverage: condition (negative path).
# A failing condition-generic command must block the release entirely --
# no tag, no version bump. This is the scenario most likely to catch a
# regression where semrel ignores a non-zero condition exit code.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
COND=$(build_plugin condition-generic condition-generic)

REPO=$(new_scenario_repo "06-condition-blocks-release")

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: add feature that should never be released"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
  - type: fix
    bump: patch
plugins:
  - path: "$COND"
    phase: condition
    args:
      command: "exit 1"
EOF

if ( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml ); then
  fail "semrel release exited 0 despite a failing condition plugin"
else
  ok "semrel release exited non-zero, as expected"
fi

assert_tag_absent "$REPO" "v0.2.0"

finish
