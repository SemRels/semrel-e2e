#!/usr/bin/env bash
# Category coverage: hook (slack, teams, matrix, jira) -- REAL execution
# against a local target.
#
# All four are just "POST/PUT JSON to a configured URL" under the hood
# (webhook_url / homeserver_url / base_url), so instead of treating them as
# opt-in-external (scenario 14), we point every one of them at the bundled
# local mock HTTP server and let the real plugin binaries make real HTTP
# calls to it. This is the primary, always-on coverage for these plugins;
# scenario 14 stays around only as an optional confidence check against a
# real Slack workspace.
#
# IMPORTANT, found by actually running this: hook-jira's actual required
# args (cmd/plugin/main.go) are SEMREL_PLUGIN_BASE_URL, _EMAIL, _API_TOKEN,
# and _PROJECT_KEY (Jira Cloud's email+API-token basic auth convention) --
# not _TOKEN/_PROJECT as its README's config table documents.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
PROV=$(build_plugin provider-git provider-git)
SLACK=$(build_plugin hook-slack hook-slack)
TEAMS=$(build_plugin hook-teams hook-teams)
MATRIX=$(build_plugin hook-matrix hook-matrix)
JIRA=$(build_plugin hook-jira hook-jira)

REPO=$(new_scenario_repo "18-hooks-http-local")

REMOTE_DIR="$WORK_DIR/18-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: notify every hook plugin at once"

LOG="$WORK_DIR/18-requests.ndjson"
ENDPOINT=$(start_mock_server "$LOG")
[[ -n "$ENDPOINT" ]] || { fail "mock server failed to start"; finish; }

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
  - path: "$SLACK"
    phase: release
    args:
      webhook_url: "$ENDPOINT/slack"
  - path: "$TEAMS"
    phase: release
    args:
      webhook_url: "$ENDPOINT/teams"
  - path: "$MATRIX"
    phase: release
    args:
      homeserver_url: "$ENDPOINT"
      token: "fake-token"
      room_id: "!fake:local"
  - path: "$JIRA"
    phase: release
    args:
      base_url: "$ENDPOINT"
      email: "semrel-e2e@local.test"
      api_token: "fake-token"
      project_key: "REL"
EOF

set +e
( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  ok "semrel release exited 0 with all four hook plugins pointed at the mock server"
else
  fail "semrel release exited $rc (see request log: $LOG)"
fi

for path in "/slack" "/teams"; do
  if grep -q "\"url\":\"$path" "$LOG" 2>/dev/null; then
    ok "mock server saw a request to $path"
  else
    fail "mock server never saw a request to $path"
  fi
done

REQS=$(wc -l < "$LOG" 2>/dev/null || echo 0)
if [[ "$REQS" -ge 4 ]]; then
  ok "mock server received $REQS requests (expected at least 4, one per hook)"
else
  fail "mock server only received $REQS requests, expected at least 4"
fi

finish
