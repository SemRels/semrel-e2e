#!/usr/bin/env bash
# Category coverage: condition (github-actions, gitlab-ci, gitea-actions).
# Each of these plugins gates on CI-provided env vars rather than config.
# For each one: verify it blocks the release outside CI, then verify it
# allows the release once the matching CI env var is simulated.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
GHA=$(build_plugin condition-github-actions condition-github-actions)
GLCI=$(build_plugin condition-gitlab-ci condition-gitlab-ci)
GITEA=$(build_plugin condition-gitea-actions condition-gitea-actions)

run_gate_case() {
  local label="$1" plugin_path="$2" env_var="$3" env_value="$4" tag="$5"
  local repo
  repo=$(new_scenario_repo "07-ci-gate-$label")

  echo "# demo" > "$repo/README.md"
  commit_all "$repo" "chore: initial commit"
  git -C "$repo" tag v0.1.0

  echo "feature" > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "feat: gated feature ($label)"

  cat > "$repo/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
plugins:
  - path: "$plugin_path"
    phase: condition
EOF

  # Case 1: not in the target CI -> must block.
  if ( cd "$repo" && env -u "$env_var" "$SEMREL_BIN" release --config .semrel.yaml ); then
    fail "$label: release succeeded without $env_var set (should have blocked)"
  else
    ok "$label: blocked outside $env_var"
  fi
  assert_tag_absent "$repo" "$tag"

  # Case 2: simulate the target CI -> must allow.
  if ( cd "$repo" && env "$env_var=$env_value" "$SEMREL_BIN" release --config .semrel.yaml ); then
    ok "$label: succeeded with $env_var=$env_value"
  else
    fail "$label: release failed even with $env_var=$env_value set"
  fi
  assert_tag_exists "$repo" "$tag"
}

run_gate_case "github-actions" "$GHA" GITHUB_ACTIONS true v0.2.0
run_gate_case "gitlab-ci" "$GLCI" GITLAB_CI true v0.2.0
run_gate_case "gitea-actions" "$GITEA" GITEA_ACTIONS true v0.2.0

finish
