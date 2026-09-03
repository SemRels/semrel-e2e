#!/usr/bin/env bash
# Category coverage: updater (npm), generator (changelog-md), provider (git).
# Proves multiple plugin categories composing in one pipeline and that
# generator-changelog-md actually writes CHANGELOG.md.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
PROV=$(build_plugin provider-git provider-git)
UPD=$(build_plugin updater-npm updater-npm)
GEN=$(build_plugin generator-changelog-md generator-changelog-md)

REPO=$(new_scenario_repo "02-updater-npm-changelog-md")

REMOTE_DIR="$WORK_DIR/02-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

cat > "$REPO/package.json" <<'EOF'
{
  "name": "e2e-demo",
  "version": "0.1.0"
}
EOF
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: add npm-updated feature"

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
  - path: "$UPD"
    phase: pre-tag
    args:
      file: package.json
  - path: "$GEN"
    phase: pre-tag
  - path: "$PROV"
    phase: release
    args:
      push_branch: "true"
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
assert_file_contains "$REPO/package.json" '"version": "0.2.0"'
assert_file_contains "$REPO/CHANGELOG.md" "0.2.0"
assert_file_contains "$REPO/CHANGELOG.md" "add npm-updated feature"

finish
