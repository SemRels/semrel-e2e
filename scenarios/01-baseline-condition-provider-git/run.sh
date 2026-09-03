#!/usr/bin/env bash
# Category coverage: condition, provider.
# The smallest real pipeline: a passing condition gate + provider-git creating
# a real (unpushed) tag. Every other scenario builds on this shape.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
COND=$(build_plugin condition-generic condition-generic)
PROV=$(build_plugin provider-git provider-git)

REPO=$(new_scenario_repo "01-baseline-condition-provider-git")

# provider-git always pushes the tag it creates, so give it a real (local)
# remote to push to instead of skipping that part of its behavior.
REMOTE_DIR="$WORK_DIR/01-baseline-condition-provider-git-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "line" > "$REPO/feature.txt"
commit_all "$REPO" "feat: add first feature"

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
      command: "true"
  - path: "$PROV"
    phase: release
    args:
      push_branch: "false"
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"

if git -C "$REMOTE_DIR" tag --list "v0.2.0" | grep -qx "v0.2.0"; then
  ok "remote origin received tag v0.2.0 (provider-git pushed it)"
else
  fail "remote origin missing tag v0.2.0 -- provider-git did not push"
fi

finish
