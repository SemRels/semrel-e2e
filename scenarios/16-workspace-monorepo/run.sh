#!/usr/bin/env bash
# Category coverage: core config feature (workspace/monorepo) combined with
# per-package updater plugins -- two independently-versioned packages, only
# one of which changed, released via `semrel workspace release`.
#
# IMPORTANT, found by actually running this: `semrel workspace release
# --config .semrel.yaml` (a RELATIVE path -- the natural thing to type) is
# broken. resolveWorkspacePackages() (semrel/internal/cli/workspace.go)
# derives each package's config path from filepath.Dir(rootConfigFile); with
# a relative root config that stays relative ("packages/api/.semrel.yaml"),
# but runWorkspaceSequential() os.Chdir()s into the package directory
# *before* opening that same relative path -- so it resolves against the
# new cwd and doubles up (looks for packages/api/packages/api/.semrel.yaml,
# which doesn't exist) with "path not found". Passing an ABSOLUTE --config
# path avoids it entirely, which is what this scenario does; a real user
# typing a relative path would hit this every time.
#
# SECOND BUG found here: `SEMREL_VERSION` passed to pre-tag plugins is
# wrong for any package with a non-trivial tagPrefix. root.go builds
# summary.NextVersion (-> SEMREL_VERSION) from `nextTag := cfg.TagPrefix +
# nextVer.String()` -- the FULL tag, not the bare version -- even though
# SEMREL_TAG_PREFIX is exported separately for exactly this purpose (see
# how hook-gitplugin's cmd/plugin/main.go correctly strips SEMREL_TAG_NAME
# by SEMREL_TAG_PREFIX). Every simple updater plugin (npm, go, cargo, ...)
# only does `strings.TrimPrefix(version, "v")` on SEMREL_VERSION -- which
# quietly works for the common single-char "v" prefix, but for a package
# tagPrefix like "packages/api@v" leaves the literal string
# "packages/api@v0.2.0" untouched, and that whole string gets written into
# package.json's version field. This scenario asserts that actual (buggy)
# output rather than hiding it -- a monorepo using the tagPrefix pattern
# the docs themselves recommend hits this on every release.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
NPM=$(build_plugin updater-npm updater-npm)

REPO=$(new_scenario_repo "16-workspace-monorepo")

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

( cd "$REPO" && "$SEMREL_BIN" workspace release --config "$(native_path "$REPO/.semrel.yaml")" )

assert_tag_exists "$REPO" "packages/api@v0.2.0"
# Documents the SEMREL_VERSION/tagPrefix bug above -- not the correct value.
assert_file_contains "$REPO/packages/api/package.json" '"version": "packages/api@v0.2.0"'

assert_tag_absent "$REPO" "packages/ui@v0.2.0"
assert_file_contains "$REPO/packages/ui/package.json" '"version": "0.1.0"'

finish
