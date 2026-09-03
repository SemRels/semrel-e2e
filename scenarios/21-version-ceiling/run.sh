#!/usr/bin/env bash
# Core config feature: version_ceiling + ceiling_strategy (clamp/skip/error).
# No plugin dependency beyond provider-git for tagging.
#
# IMPORTANT, found by actually running this: "clamp" does not mean what
# semrel/docs/config-reference.md says ("Release at version_ceiling instead
# of the higher computed version"). The real implementation
# (pkg/semver/calculator.go ApplyCeiling/clampedCandidates) instead steps
# DOWN to the next-smaller bump size that stays under the ceiling -- a
# major bump retries as current.Minor+1, a major-or-minor bump retries as
# current.Patch+1 -- and uses THAT, not the literal ceiling value. With
# current=0.1.0, a computed minor bump to 0.2.0, and ceiling=0.1.5, the
# real clamped result is 0.1.1 (patch+1), never 0.1.5.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
PROV=$(build_plugin provider-git provider-git)

setup_case() {
  local label="$1"
  local repo
  repo=$(new_scenario_repo "21-ceiling-$label")

  local remote_dir="$WORK_DIR/21-ceiling-$label-remote.git"
  rm -rf "$remote_dir"
  git init -q --bare -b main "$remote_dir"
  git -C "$repo" remote add origin "$remote_dir"

  echo "# demo" > "$repo/README.md"
  commit_all "$repo" "chore: initial commit"
  git -C "$repo" tag v0.1.0
  git -C "$repo" push -q origin main --tags
  echo "feature" > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "feat: this would normally bump to v0.2.0"
  echo "$repo"
}

write_config() {
  local repo="$1" strategy="$2"
  cat > "$repo/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
version_ceiling: "0.1.5"
ceiling_strategy: $strategy
plugins:
  - path: "$PROV"
    phase: release
    args:
      push_branch: "false"
EOF
}

# clamp: steps down to the next-smaller bump that stays under the ceiling
# (v0.1.1, a patch bump) -- NOT literally v0.1.5. See header comment.
REPO_CLAMP=$(setup_case "clamp")
write_config "$REPO_CLAMP" "clamp"
( cd "$REPO_CLAMP" && "$SEMREL_BIN" release --config .semrel.yaml )
assert_tag_exists "$REPO_CLAMP" "v0.1.1"
assert_tag_absent "$REPO_CLAMP" "v0.1.5"
assert_tag_absent "$REPO_CLAMP" "v0.2.0"

# skip: no release at all, clean exit.
REPO_SKIP=$(setup_case "skip")
write_config "$REPO_SKIP" "skip"
set +e
( cd "$REPO_SKIP" && "$SEMREL_BIN" release --config .semrel.yaml )
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ok "skip: semrel release exited 0 (clean skip)"
else
  fail "skip: semrel release exited $rc, expected a clean (0) skip"
fi
assert_tag_absent "$REPO_SKIP" "v0.1.5"
assert_tag_absent "$REPO_SKIP" "v0.2.0"

# error: non-zero exit, no tag.
REPO_ERROR=$(setup_case "error")
write_config "$REPO_ERROR" "error"
if ( cd "$REPO_ERROR" && "$SEMREL_BIN" release --config .semrel.yaml ); then
  fail "error: semrel release exited 0, expected a non-zero error exit"
else
  ok "error: semrel release exited non-zero, as expected"
fi
assert_tag_absent "$REPO_ERROR" "v0.1.5"
assert_tag_absent "$REPO_ERROR" "v0.2.0"

finish
