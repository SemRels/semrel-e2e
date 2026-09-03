#!/usr/bin/env bash
# Category coverage: updater (cargo, python) composed in one release.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
CARGO=$(build_plugin updater-cargo updater-cargo)
PY=$(build_plugin updater-python updater-python)

REPO=$(new_scenario_repo "04-updater-cargo-python")

cat > "$REPO/Cargo.toml" <<'EOF'
[package]
name = "e2e-demo"
version = "0.1.0"
edition = "2021"
EOF

cat > "$REPO/pyproject.toml" <<'EOF'
[project]
name = "e2e-demo"
version = "0.1.0"
EOF

commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: add cross-language feature"

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
  - path: "$CARGO"
    phase: pre-tag
    args:
      file: Cargo.toml
  - path: "$PY"
    phase: pre-tag
    args:
      file: pyproject.toml
      backend: pyproject
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
assert_file_contains "$REPO/Cargo.toml" 'version = "0.2.0"'
assert_file_contains "$REPO/pyproject.toml" 'version = "0.2.0"'

finish
