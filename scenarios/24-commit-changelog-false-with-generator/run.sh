#!/usr/bin/env bash
# Core config feature: commit_changelog: false, delegating CHANGELOG.md
# entirely to a pre-tag generator plugin instead of semrel's built-in
# writer. Per semrel/docs/config-reference.md, generator-changelog-md only
# writes CHANGELOG.md to disk (rather than just stdout) when keep_releases
# is set, so this scenario doubles as a check that that documented
# requirement is real.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
GEN=$(build_plugin generator-changelog-md generator-changelog-md)
PROV=$(build_plugin provider-git provider-git)

REPO=$(new_scenario_repo "24-commit-changelog-false-with-generator")

REMOTE_DIR="$WORK_DIR/24-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: changelog is entirely the plugin's job now"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
commit_changelog: false
plugins:
  - path: "$GEN"
    phase: pre-tag
    args:
      keep_releases: "10"
  - path: "$PROV"
    phase: release
    args:
      push_branch: "true"
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
assert_file_contains "$REPO/CHANGELOG.md" "0.2.0"
assert_file_contains "$REPO/CHANGELOG.md" "changelog is entirely the plugin's job now"

finish
