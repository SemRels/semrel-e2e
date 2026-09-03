#!/usr/bin/env bash
# Category coverage: publisher (oci).
# Like packager-nfpm, this is documented as "planned" upstream and not
# wired into the semrel release pipeline's phases yet, so this invokes the
# plugin binary directly (same env-var contract semrel's orchestrator would
# use). It shells out to the real `oras` CLI
# (go install oras.land/oras/cmd/oras@latest).
#
# Tried and reverted: a local plain-HTTP registry (github.com/distribution/
# distribution's `registry` binary, no Docker needed) DOES work as a real
# OCI registry, but publisher-oci's own BuildOrasArgs() (internal/plugin/
# provider.go) hardcodes `oras push <ref> <artifacts...>` with no
# `--plain-http`/`--insecure` flag and no env var to add one -- oras then
# refuses with "server gave HTTP response to HTTPS client". Making that
# succeed would need a registry with a certificate the system already
# trusts, which means either a real hosted registry or adding a
# self-signed CA to the OS trust store -- the latter is a system security
# change out of scope for a test scenario. So this genuinely needs
# SEMREL_E2E_OCI_REF pointing at a real, already-trusted registry
# (ghcr.io/..., a company registry, etc.) you're authenticated to via
# `oras login` or Docker credential helpers. Skips itself otherwise.
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
