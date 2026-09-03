#!/usr/bin/env bash
# Category coverage: provider (github, gitlab, gitea, bitbucket) against a
# REAL external platform.
#
# Opt-in only. This scenario, when actually run, creates a real release on
# a real repository -- it is deliberately skipped unless you export
# credentials for at least one platform. Never runs in CI by default.
#
# To enable GitHub:
#   export SEMREL_E2E_GITHUB_TOKEN=ghp_...
#   export SEMREL_E2E_GITHUB_OWNER=your-user-or-org
#   export SEMREL_E2E_GITHUB_REPO=a-scratch-repo-you-own
# GitLab / Gitea / Bitbucket follow the same SEMREL_E2E_<PLATFORM>_* pattern;
# add a block below mirroring the GitHub one once you have credentials for
# them (see provider-gitlab/gitlab, provider-gitea, provider-bitbucket
# READMEs in the workspace root for their exact SEMREL_PLUGIN_* fields).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

if [[ -z "${SEMREL_E2E_GITHUB_TOKEN:-}" ]]; then
  skip "requires SEMREL_E2E_GITHUB_TOKEN (+ _OWNER/_REPO of a real scratch repo you own) -- see this file's header"
fi
require_env SEMREL_E2E_GITHUB_OWNER SEMREL_E2E_GITHUB_REPO

build_semrel
COND=$(build_plugin condition-generic condition-generic)
PROV=$(build_plugin provider-github provider-github)

REPO=$(new_scenario_repo "13-provider-external-github")

REMOTE_URL="https://github.com/${SEMREL_E2E_GITHUB_OWNER}/${SEMREL_E2E_GITHUB_REPO}.git"
git -C "$REPO" remote add origin "$REMOTE_URL"

echo "# e2e external provider scratch commit" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0
git -C "$REPO" push -q origin main --tags --force

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: real github release from semrel-e2e"
git -C "$REPO" push -q origin main

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
plugins:
  - path: "$COND"
    phase: condition
    args:
      command: "true"
  - path: "$PROV"
    phase: release
    args:
      token: "$SEMREL_E2E_GITHUB_TOKEN"
      owner: "$SEMREL_E2E_GITHUB_OWNER"
      repo: "$SEMREL_E2E_GITHUB_REPO"
      draft: "true"
EOF

( cd "$REPO" && SEMREL_PLUGIN_TOKEN="$SEMREL_E2E_GITHUB_TOKEN" "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
ok "check https://github.com/${SEMREL_E2E_GITHUB_OWNER}/${SEMREL_E2E_GITHUB_REPO}/releases for a draft v0.2.0 release"

finish
