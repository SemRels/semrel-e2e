#!/usr/bin/env bash
# Category coverage: hook (gitplugin).
#
# IMPORTANT, found by actually running this: hook-gitplugin's README
# describes it as mirroring the release to a second repository via
# SEMREL_PLUGIN_REPO/BRANCH/TOKEN. The real implementation
# (hook-gitplugin/cmd/plugin/main.go) reads no such REPO variable at all --
# it runs `git tag`/`git push` in whatever directory semrel itself is
# running in (os.Getwd()), i.e. the SAME repo and SAME remote as the main
# release, not a second one. Its actual configurable surface is
# SEMREL_PLUGIN_TAG_NAME/TAG_MESSAGE/COMMIT_MESSAGE/REMOTE/BRANCH/FILES/
# SIGN_TAG/SIGNED_OFF_BY.
#
# Consequence: since semrel's core pipeline already creates the primary
# release tag before any release-phase plugin runs, hook-gitplugin would
# collide with it ("tag already exists", git exit 128) unless given a
# *different* tag name -- which is what this scenario does (a "mirror-v..."
# tag in the same repo/remote), reflecting what the plugin actually does
# rather than what its README describes.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
HOOK=$(build_plugin hook-gitplugin hook-gitplugin)

REPO=$(new_scenario_repo "09-hook-gitplugin-local-mirror")

REMOTE_DIR="$WORK_DIR/09-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: tag this release a second way via hook-gitplugin"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
plugins:
  - path: "$HOOK"
    phase: release
    args:
      tag_name: "mirror-v{version}"
      branch: main
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
assert_tag_exists "$REPO" "mirror-v0.2.0"

if git -C "$REMOTE_DIR" tag --list "mirror-v0.2.0" | grep -qx "mirror-v0.2.0"; then
  ok "remote origin received the mirror-v0.2.0 tag pushed by hook-gitplugin"
else
  fail "remote origin missing mirror-v0.2.0 -- hook-gitplugin did not push it"
fi

finish
