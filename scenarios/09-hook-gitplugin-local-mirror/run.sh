#!/usr/bin/env bash
# Category coverage: hook (gitplugin).
# hook-gitplugin pushes the release tag to a second repository. We point it
# at a local bare repo instead of a real GitHub mirror -- fully real
# execution, zero external services or credentials involved.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
PROV=$(build_plugin provider-git provider-git)
HOOK=$(build_plugin hook-gitplugin hook-gitplugin)

REPO=$(new_scenario_repo "09-hook-gitplugin-local-mirror")

ORIGIN_DIR="$WORK_DIR/09-origin.git"
MIRROR_DIR="$WORK_DIR/09-mirror.git"
rm -rf "$ORIGIN_DIR" "$MIRROR_DIR"
git init -q --bare -b main "$ORIGIN_DIR"
git init -q --bare -b main "$MIRROR_DIR"
git -C "$REPO" remote add origin "$ORIGIN_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: mirror this release to a second repo"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
plugins:
  - path: "$PROV"
    phase: release
    args:
      push_branch: "true"
  - path: "$HOOK"
    phase: release
    args:
      repo: "$(native_path "$MIRROR_DIR")"
      branch: main
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"

if git -C "$MIRROR_DIR" tag --list "v0.2.0" | grep -qx "v0.2.0"; then
  ok "mirror repo received tag v0.2.0 via hook-gitplugin"
else
  fail "mirror repo missing tag v0.2.0 -- hook-gitplugin did not push it"
fi

finish
