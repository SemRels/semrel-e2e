#!/usr/bin/env bash
# Category coverage: provider (gitlab, gitea) -- REAL execution against a
# local target instead of the opt-in-external path used for github/bitbucket.
#
# Both plugins expose a configurable base URL (SEMREL_PLUGIN_BASE_URL),
# unlike provider-github/provider-bitbucket which hardcode their API host.
# That means we can point them at scripts/mock-http-server and get a real
# HTTP call out of the real plugin binary without any account or token.
#
# Caveat: the mock server always answers 200 with a generic {"ok":true}
# body, not a real GitLab/Gitea release JSON payload. If either plugin
# expects specific response fields (e.g. a release id/url) it may still
# fail here -- that failure is real signal about the plugin's response
# handling, not a scenario bug. Check the request log either way.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
GITLAB=$(build_plugin provider-gitlab provider-gitlab)
GITEA=$(build_plugin provider-gitea provider-gitea)

REPO=$(new_scenario_repo "17-provider-gitlab-gitea-local")

REMOTE_DIR="$WORK_DIR/17-remote.git"
rm -rf "$REMOTE_DIR"
git init -q --bare -b main "$REMOTE_DIR"
git -C "$REPO" remote add origin "$REMOTE_DIR"

echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: release via local-mocked gitlab/gitea"

LOG="$WORK_DIR/17-requests.ndjson"
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
  - path: "$GITLAB"
    phase: release
    args:
      base_url: "$ENDPOINT"
      project_id: "1"
      token: "fake-token"
  - path: "$GITEA"
    phase: release
    args:
      base_url: "$ENDPOINT"
      owner: "acme"
      repo: "e2e-demo"
      token: "fake-token"
EOF

set +e
( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  ok "semrel release exited 0 with both provider plugins pointed at the mock server"
else
  fail "semrel release exited $rc (see request log for what each provider actually sent: $LOG)"
fi

REQS=$(wc -l < "$LOG" 2>/dev/null || echo 0)
if [[ "$REQS" -ge 1 ]]; then
  ok "mock server received $REQS request(s) from the provider plugins"
else
  fail "mock server received zero requests -- neither provider called out"
fi

finish
