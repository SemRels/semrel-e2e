#!/usr/bin/env bash
# Category coverage: publisher (oci).
# Like packager-nfpm, this is documented as "planned" upstream and not wired
# into the semrel release pipeline's phases yet, and it shells out to the
# real `oras` CLI, which also needs a real (or locally-run) OCI registry to
# push to -- there's no equivalent of "point a URL arg at a mock server"
# here, since OCI push is a multi-step protocol (blob sessions, manifest
# PUT, ...) a generic HTTP mock can't satisfy. Skips itself (exit 77) unless
# `oras` is installed; even then, set SEMREL_E2E_OCI_REF to a registry you
# can actually push to (e.g. a local `registry:2` container, or a real
# ghcr.io/... ref you're authenticated for) to run it for real.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

require_cmd oras
require_env SEMREL_E2E_OCI_REF

PUB=$(build_plugin publisher-oci publisher-oci)

REPO=$(new_scenario_repo "20-publisher-oci")
mkdir -p "$REPO/dist"
echo "artifact-bytes" > "$REPO/dist/e2e-demo-linux-amd64"

set +e
(
  cd "$REPO"
  export SEMREL_VERSION=0.2.0
  export SEMREL_NEXT_VERSION=0.2.0
  export SEMREL_DRY_RUN=false
  export SEMREL_PLUGIN_REF="$SEMREL_E2E_OCI_REF"
  export SEMREL_PLUGIN_ARTIFACTS=dist/e2e-demo-linux-amd64
  "$PUB"
)
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  ok "publisher-oci exited 0 against $SEMREL_E2E_OCI_REF"
else
  fail "publisher-oci exited $rc"
fi

finish
