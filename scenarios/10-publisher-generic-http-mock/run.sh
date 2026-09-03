#!/usr/bin/env bash
# Category coverage: publisher (generic-http).
# publisher-generic-http is documented as "planned" in semrel/docs/config-reference.md
# and is not yet wired into the semrel release pipeline (only condition,
# pre-tag, and release phases are). We therefore invoke the built plugin
# binary directly, the same way semrel's subprocess orchestrator would:
# SEMREL_* / SEMREL_PLUGIN_* env vars in, exit code + stdout out. The target
# is a local mock HTTP server (scripts/mock-http-server), never a real
# endpoint. If this scenario fails, it's real signal that either the plugin
# or its documented contract has drifted.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

PUB=$(build_plugin publisher-generic-http publisher-generic-http)

REPO=$(new_scenario_repo "10-publisher-generic-http-mock")
mkdir -p "$REPO/dist"
echo "artifact-bytes" > "$REPO/dist/e2e-demo-linux-amd64"

LOG="$WORK_DIR/10-requests.ndjson"
ENDPOINT=$(start_mock_server "$LOG")
[[ -n "$ENDPOINT" ]] || { fail "mock server failed to start"; finish; }

set +e
(
  cd "$REPO"
  export SEMREL_VERSION=0.2.0
  export SEMREL_NEXT_VERSION=0.2.0
  export SEMREL_DRY_RUN=false
  export SEMREL_PLUGIN_URL="$ENDPOINT/releases/{version}/{artifact}"
  export SEMREL_PLUGIN_METHOD=PUT
  export SEMREL_PLUGIN_ARTIFACTS=dist/e2e-demo-linux-amd64
  "$PUB"
)
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  ok "publisher-generic-http exited 0"
else
  fail "publisher-generic-http exited $rc"
fi

if [[ -s "$LOG" ]] && grep -q "e2e-demo-linux-amd64" "$LOG"; then
  ok "mock server received a request referencing the artifact"
else
  fail "mock server did not receive the expected request (log: $LOG)"
fi

finish
