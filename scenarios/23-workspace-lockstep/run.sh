#!/usr/bin/env bash
# Core config feature: workspace strategy "lockstep" -- unlike scenario 16
# (independent), every package should share the same version even though
# only one package's files changed.
#
# Uses an ABSOLUTE --config path -- see scenario 16's header for why a
# relative one breaks `semrel workspace release`.
#
# IMPORTANT, found by actually running this: lockstep's shared-version
# computation is broken. runWorkspaceLockstep() (workspace.go) captures
# each package's `semrel release --dry-run --output json` stdout and
# extracts "current_version" by searching for the literal substring
# `"current_version":"` (no space). But `semrel release --output json`
# actually pretty-prints with a space after the colon --
# `"current_version": "packages/api@v0.1.0"` -- so the search never
# matches, currentVersionStr stays empty, ParseVersion("") fails, and the
# code falls back to treating current version as 0.0.0 for every package.
# A "minor" bump from a fake 0.0.0 baseline gives 0.1.0, not the real
# 0.2.0. (The sibling bump-level scraping code a few lines up specifically
# checks BOTH `"bump":"major"` and `"bump": "major"` variants -- this one
# doesn't, which is the actual gap.)
#
# Because this scenario's fixture pre-tags both packages at v0.1.0 (a
# realistic monorepo starting state), the miscalculated 0.1.0 target
# happens to collide with that already-existing tag, so
# tag_exists_strategy's default "update-changelog" path silently takes
# over instead of loudly failing: no new tag, no package.json update, just
# a rewritten CHANGELOG.md. This scenario asserts that real (buggy,
# silently-no-op) outcome.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
NPM=$(build_plugin updater-npm updater-npm)

REPO=$(new_scenario_repo "23-workspace-lockstep")

mkdir -p "$REPO/packages/api" "$REPO/packages/ui"
cat > "$REPO/packages/api/package.json" <<'EOF'
{
  "name": "api",
  "version": "0.1.0"
}
EOF
cat > "$REPO/packages/ui/package.json" <<'EOF'
{
  "name": "ui",
  "version": "0.1.0"
}
EOF

commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag "packages/api@v0.1.0"
git -C "$REPO" tag "packages/ui@v0.1.0"

# Only api changes -- lockstep should still bump ui to the same version.
echo "handler" > "$REPO/packages/api/handler.txt"
git -C "$REPO" add packages/api/handler.txt
git -C "$REPO" commit -q -m "feat(api): add new handler"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
branches:
  - name: main
rules:
  - type: feat
    bump: minor
  - type: fix
    bump: patch
workspace:
  strategy: lockstep
  packages:
    - path: packages/api
      tagPrefix: "packages/api@v"
    - path: packages/ui
      tagPrefix: "packages/ui@v"
EOF

for pkg in api ui; do
  cat > "$REPO/packages/$pkg/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "packages/$pkg@v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
  - type: fix
    bump: patch
plugins:
  - path: "$NPM"
    phase: pre-tag
    args:
      file: package.json
EOF
done

OUTPUT=$( cd "$REPO" && "$SEMREL_BIN" workspace release --config "$(native_path "$REPO/.semrel.yaml")" 2>&1 )
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "lockstep: shared next version = 0.1.0"; then
  ok "reproduced the lockstep JSON-scraping bug: shared version miscomputed as 0.1.0"
else
  fail "expected the buggy 'shared next version = 0.1.0' -- if this now says 0.2.0, the bug was fixed upstream; update this scenario's assertions to the correct behavior"
fi

# No new tags: the miscalculated 0.1.0 target collides with the pre-existing
# v0.1.0 tags, so tag_exists_strategy=update-changelog (the default) takes
# over silently instead of releasing.
assert_tag_absent "$REPO" "packages/api@v0.2.0"
assert_tag_absent "$REPO" "packages/ui@v0.2.0"
assert_file_contains "$REPO/packages/api/package.json" '"version": "0.1.0"'
assert_file_contains "$REPO/packages/ui/package.json" '"version": "0.1.0"'

finish
