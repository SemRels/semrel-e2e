#!/usr/bin/env bash
# Category coverage: core config feature (workspace/monorepo) combined with
# per-package updater plugins -- two independently-versioned packages, only
# one of which changed, released via `semrel workspace release`.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
NPM=$(build_plugin updater-npm updater-npm)

REPO=$(new_scenario_repo "16-workspace-monorepo")

mkdir -p "$REPO/packages/api" "$REPO/packages/ui"
cat > "$REPO/packages/api/package.json" <<'EOF'
{ "name": "api", "version": "0.1.0" }
EOF
cat > "$REPO/packages/ui/package.json" <<'EOF'
{ "name": "ui", "version": "0.1.0" }
EOF

commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag "packages/api@v0.1.0"
git -C "$REPO" tag "packages/ui@v0.1.0"

# Only the api package changes in this release.
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
  strategy: independent
  packages:
    - path: packages/api
      tagPrefix: "packages/api@v"
    - path: packages/ui
      tagPrefix: "packages/ui@v"
EOF

cat > "$REPO/packages/api/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "packages/api@v"
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

cat > "$REPO/packages/ui/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "packages/ui@v"
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

( cd "$REPO" && "$SEMREL_BIN" workspace release --config .semrel.yaml )

assert_tag_exists "$REPO" "packages/api@v0.2.0"
assert_file_contains "$REPO/packages/api/package.json" '"version": "0.2.0"'

assert_tag_absent "$REPO" "packages/ui@v0.2.0"
assert_file_contains "$REPO/packages/ui/package.json" '"version": "0.1.0"'

finish
