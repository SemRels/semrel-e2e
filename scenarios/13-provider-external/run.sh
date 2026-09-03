#!/usr/bin/env bash
# Category coverage: provider (github, bitbucket) against a REAL external
# platform.
#
# gitlab/gitea are covered locally in scenario 17 (they accept a
# configurable base URL, so they can target the bundled mock server for
# real). github and bitbucket hardcode their API host, so there is no local
# equivalent -- they stay opt-in-external here.
#
# Each block below is independently opt-in: it runs for real (creating an
# actual draft release on a repo you own) only if its own SEMREL_E2E_*
# credentials are set, and is silently skipped otherwise. The whole
# scenario reports SKIP only if none of the blocks had credentials.
#
# To enable GitHub:
#   export SEMREL_E2E_GITHUB_TOKEN=ghp_...
#   export SEMREL_E2E_GITHUB_OWNER=your-user-or-org
#   export SEMREL_E2E_GITHUB_REPO=a-scratch-repo-you-own
# To enable Bitbucket:
#   export SEMREL_E2E_BITBUCKET_APP_PASSWORD=...
#   export SEMREL_E2E_BITBUCKET_USERNAME=your-bitbucket-username
#   export SEMREL_E2E_BITBUCKET_WORKSPACE=your-workspace
#   export SEMREL_E2E_BITBUCKET_REPO=a-scratch-repo-you-own
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
RAN_ANY=0

if [[ -n "${SEMREL_E2E_GITHUB_TOKEN:-}" && -n "${SEMREL_E2E_GITHUB_OWNER:-}" && -n "${SEMREL_E2E_GITHUB_REPO:-}" ]]; then
  RAN_ANY=1
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

  if ( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml ); then
    ok "github: semrel release exited 0"
  else
    fail "github: semrel release exited non-zero"
  fi
  assert_tag_exists "$REPO" "v0.2.0"
  ok "github: check https://github.com/${SEMREL_E2E_GITHUB_OWNER}/${SEMREL_E2E_GITHUB_REPO}/releases for a draft v0.2.0 release"
else
  echo "  [SKIP] github block: requires SEMREL_E2E_GITHUB_TOKEN/_OWNER/_REPO"
fi

if [[ -n "${SEMREL_E2E_BITBUCKET_APP_PASSWORD:-}" && -n "${SEMREL_E2E_BITBUCKET_USERNAME:-}" && -n "${SEMREL_E2E_BITBUCKET_WORKSPACE:-}" && -n "${SEMREL_E2E_BITBUCKET_REPO:-}" ]]; then
  RAN_ANY=1
  PROV_BB=$(build_plugin provider-bitbucket provider-bitbucket)
  REPO_BB=$(new_scenario_repo "13-provider-external-bitbucket")

  REMOTE_URL_BB="https://${SEMREL_E2E_BITBUCKET_USERNAME}:${SEMREL_E2E_BITBUCKET_APP_PASSWORD}@bitbucket.org/${SEMREL_E2E_BITBUCKET_WORKSPACE}/${SEMREL_E2E_BITBUCKET_REPO}.git"
  git -C "$REPO_BB" remote add origin "$REMOTE_URL_BB"

  echo "# e2e external provider scratch commit" > "$REPO_BB/README.md"
  commit_all "$REPO_BB" "chore: initial commit"
  git -C "$REPO_BB" tag v0.1.0
  git -C "$REPO_BB" push -q origin main --tags --force

  echo "feature" > "$REPO_BB/feature.txt"
  git -C "$REPO_BB" add feature.txt
  git -C "$REPO_BB" commit -q -m "feat: real bitbucket release from semrel-e2e"
  git -C "$REPO_BB" push -q origin main

  cat > "$REPO_BB/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
plugins:
  - path: "$PROV_BB"
    phase: release
    args:
      workspace: "$SEMREL_E2E_BITBUCKET_WORKSPACE"
      repo: "$SEMREL_E2E_BITBUCKET_REPO"
      app_password: "$SEMREL_E2E_BITBUCKET_APP_PASSWORD"
      username: "$SEMREL_E2E_BITBUCKET_USERNAME"
EOF

  if ( cd "$REPO_BB" && "$SEMREL_BIN" release --config .semrel.yaml ); then
    ok "bitbucket: semrel release exited 0"
  else
    fail "bitbucket: semrel release exited non-zero"
  fi
  assert_tag_exists "$REPO_BB" "v0.2.0"
else
  echo "  [SKIP] bitbucket block: requires SEMREL_E2E_BITBUCKET_APP_PASSWORD/_USERNAME/_WORKSPACE/_REPO"
fi

if [[ "$RAN_ANY" -eq 0 ]]; then
  skip "no external provider credentials set -- see this file's header"
fi

finish
