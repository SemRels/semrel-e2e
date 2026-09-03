#!/usr/bin/env bash
# Category coverage: core config feature (prerelease channels) combined with
# a real provider plugin -- proves prerelease branches and plugins compose.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
PROV=$(build_plugin provider-git provider-git)

REPO=$(new_scenario_repo "15-prerelease-channel")

REMOTE_DIR="$WORK_DIR/15-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

git -C "$REPO" checkout -q -b next

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: preview this on the next channel"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
  - name: next
    prerelease: next
rules:
  - type: feat
    bump: minor
plugins:
  - path: "$PROV"
    phase: release
    args:
      push_branch: "true"
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

if git -C "$REPO" tag --list | grep -Eq '^v0\.2\.0-next\.[0-9]+$'; then
  ok "prerelease tag matching v0.2.0-next.N created: $(git -C "$REPO" tag --list | grep -E '^v0\.2\.0-next\.')"
else
  fail "no v0.2.0-next.N tag found (found: $(git -C "$REPO" tag --list | tr '\n' ' '))"
fi

finish
