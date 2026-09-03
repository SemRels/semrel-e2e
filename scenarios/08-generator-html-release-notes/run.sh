#!/usr/bin/env bash
# Category coverage: generator (changelog-html, release-notes).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
HTML=$(build_plugin generator-changelog-html generator-changelog-html)
NOTES=$(build_plugin generator-release-notes generator-release-notes)
PROV=$(build_plugin provider-git provider-git)

REPO=$(new_scenario_repo "08-generator-html-release-notes")

REMOTE_DIR="$WORK_DIR/08-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: add release-notes worthy feature"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
plugins:
  - path: "$HTML"
    phase: pre-tag
    args:
      max_commits: "50"
  - path: "$NOTES"
    phase: pre-tag
    args:
      max_commits: "50"
  - path: "$PROV"
    phase: release
    args:
      push_branch: "true"
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"

finish
