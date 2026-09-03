#!/usr/bin/env bash
# Category coverage: updater (go), condition (generic).
# Mirrors semrel/scripts/local-demo.sh but as a repeatable, assertable scenario.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
COND=$(build_plugin condition-generic condition-generic)
UPD=$(build_plugin updater-go updater-go)

REPO=$(new_scenario_repo "03-updater-go")

mkdir -p "$REPO/internal/version"
cat > "$REPO/internal/version/version.go" <<'EOF'
package version

const Version = "0.1.0"
EOF
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: add demo capability"

echo "fix" > "$REPO/fix.txt"
git -C "$REPO" add fix.txt
git -C "$REPO" commit -q -m "fix: patch demo behavior"

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
      command: "test -f internal/version/version.go"
  - path: "$UPD"
    phase: pre-tag
    args:
      file: internal/version/version.go
      variable: Version
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
assert_file_contains "$REPO/internal/version/version.go" '0.2.0'

finish
