#!/usr/bin/env bash
# Category coverage: packager (nfpm).
# packager-nfpm is documented as "planned" and, like the publishers, is not
# yet wired into the semrel release pipeline's phases (condition/pre-tag/
# release). It also shells out to the real `nfpm` binary, which most dev
# machines won't have installed (get it with
# `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest`). This
# scenario invokes the plugin binary directly and skips itself (exit 77)
# when `nfpm` isn't on PATH, so it never fails CI/dev runs that simply lack
# the optional dependency -- but runs for real wherever nfpm is available.
#
# SEMREL_PLUGIN_TARGET is passed straight through as nfpm's own --target
# flag: with a single packager requested, nfpm treats a path with no
# recognized package extension as the literal OUTPUT FILE, not a
# directory -- so this deliberately targets "dist" (a directory, matching
# packager-nfpm's own test suite) and nfpm auto-names the file inside it.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

require_cmd nfpm

PKG=$(build_plugin packager-nfpm packager-nfpm)

REPO=$(new_scenario_repo "11-packager-nfpm")
mkdir -p "$REPO/dist" "$REPO/packaging"
echo "#!/bin/sh" > "$REPO/dist/e2e-demo"
chmod +x "$REPO/dist/e2e-demo"

cat > "$REPO/packaging/nfpm.yaml" <<'EOF'
name: e2e-demo
arch: amd64
platform: linux
version: 0.2.0
contents:
  - src: dist/e2e-demo
    dst: /usr/bin/e2e-demo
EOF

set +e
(
  cd "$REPO"
  export SEMREL_VERSION=0.2.0
  export SEMREL_NEXT_VERSION=0.2.0
  export SEMREL_DRY_RUN=false
  export SEMREL_PLUGIN_CONFIG=packaging/nfpm.yaml
  export SEMREL_PLUGIN_TARGET=dist
  export SEMREL_PLUGIN_PACKAGERS=deb
  "$PKG"
)
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  ok "packager-nfpm exited 0"
else
  fail "packager-nfpm exited $rc"
fi

if compgen -G "$REPO/dist/*.deb" > /dev/null; then
  ok "a .deb package was produced in dist/"
else
  fail "no .deb package found in dist/"
fi

finish
