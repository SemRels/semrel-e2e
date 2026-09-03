#!/usr/bin/env bash
# Category coverage: hook (slack) against a REAL external endpoint.
#
# Optional. Scenario 18 already exercises hook-slack/teams/matrix/jira for
# real against a local mock server -- that's the primary, always-on
# coverage for this category. This scenario exists only as an extra
# confidence check against a real Slack workspace, if you want it.
#
# Opt-in only. When actually run this posts a real message to a real Slack
# channel. Skipped unless SEMREL_E2E_SLACK_WEBHOOK_URL is set.
#
# To enable Slack:
#   export SEMREL_E2E_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

if [[ -z "${SEMREL_E2E_SLACK_WEBHOOK_URL:-}" ]]; then
  skip "requires SEMREL_E2E_SLACK_WEBHOOK_URL -- see this file's header"
fi

build_semrel
PROV=$(build_plugin provider-git provider-git)
HOOK=$(build_plugin hook-slack hook-slack)

REPO=$(new_scenario_repo "14-hooks-external-slack")

REMOTE_DIR="$WORK_DIR/14-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: real slack notification from semrel-e2e"

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
      webhook_url: "$SEMREL_E2E_SLACK_WEBHOOK_URL"
      channel: "#semrel-e2e-test"
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
ok "check the Slack channel for a v0.2.0 release notification"

finish
