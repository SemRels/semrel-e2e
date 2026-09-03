#!/usr/bin/env bash
# Category coverage: hook (email) -- REAL execution against a local SMTP
# catcher (scripts/mock-smtp-server) instead of a real mail server.
# The mock server is plaintext-only (no STARTTLS), so this scenario must
# set SEMREL_PLUGIN_TLS=false to match.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
PROV=$(build_plugin provider-git provider-git)
EMAIL=$(build_plugin hook-email hook-email)

REPO=$(new_scenario_repo "19-hook-email-local-smtp")

REMOTE_DIR="$WORK_DIR/19-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: email the team about this release"

LOG="$WORK_DIR/19-messages.ndjson"
SMTP_PORT=$(start_mock_smtp_server "$LOG")
[[ -n "$SMTP_PORT" ]] || { fail "mock SMTP server failed to start"; finish; }

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
  - path: "$EMAIL"
    phase: release
    args:
      smtp_host: "127.0.0.1"
      smtp_port: "$SMTP_PORT"
      smtp_user: "semrel-e2e"
      smtp_pass: "unused"
      from: "semrel-e2e@local.test"
      to: "team@local.test"
      tls: "false"
EOF

set +e
( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  ok "semrel release exited 0 with hook-email pointed at the local SMTP catcher"
else
  fail "semrel release exited $rc (see message log: $LOG)"
fi

if [[ -s "$LOG" ]] && grep -q "team@local.test" "$LOG"; then
  ok "mock SMTP server received a message addressed to team@local.test"
else
  fail "mock SMTP server never received a message (log: $LOG)"
fi

finish
