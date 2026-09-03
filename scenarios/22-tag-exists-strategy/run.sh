#!/usr/bin/env bash
# Core config feature: tag_exists_strategy (update-changelog/skip/error) --
# what semrel does when the computed next tag already exists (e.g. a
# previous run created it but a later step failed, and the release is
# retried).
#
# IMPORTANT, found by actually running this: semrel's "current version"
# detection resolves to the highest tag reachable from HEAD -- so simply
# pre-creating a v0.2.0 tag on the same commit as the feature commit (the
# obvious way to write this test) makes semrel see v0.2.0 as *current*
# too, compute "nothing to release", and never reach the tag_exists_strategy
# code path (semrel/internal/cli/root.go, step 10, right after next-version
# is computed) at all. To actually trigger it, v0.2.0 needs to exist as a
# tag ref *without* being in main's ancestry: this creates it on a
# throwaway orphan branch, deletes the branch, and keeps the now-dangling
# tag -- current-version detection still lands on v0.1.0 from main's real
# history, computes next=v0.2.0, and only then discovers a v0.2.0 tag ref
# already exists.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel

setup_case() {
  local label="$1"
  local repo
  repo=$(new_scenario_repo "22-tag-exists-$label")
  echo "# demo" > "$repo/README.md"
  commit_all "$repo" "chore: initial commit"
  git -C "$repo" tag v0.1.0

  # Create v0.2.0 on a throwaway branch not reachable from main, then drop
  # the branch -- the tag ref stays, dangling, without being "current".
  git -C "$repo" checkout -q -b tmp-orphan
  echo "unrelated" > "$repo/orphan.txt"
  git -C "$repo" add orphan.txt
  git -C "$repo" commit -q -m "chore: unrelated commit that happens to get tagged v0.2.0"
  git -C "$repo" tag v0.2.0
  git -C "$repo" checkout -q main
  git -C "$repo" branch -q -D tmp-orphan

  echo "feature" > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "feat: this computes to v0.2.0, whose tag already exists elsewhere"
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
tag_exists_strategy: $strategy
EOF
}

# update-changelog: write/update CHANGELOG.md, don't fail, don't move the tag.
REPO_UC=$(setup_case "update-changelog")
write_config "$REPO_UC" "update-changelog"
BEFORE_SHA=$(git -C "$REPO_UC" rev-list -n1 v0.2.0)
if ( cd "$REPO_UC" && "$SEMREL_BIN" release --config .semrel.yaml ); then
  ok "update-changelog: semrel release exited 0"
else
  fail "update-changelog: semrel release exited non-zero"
fi
assert_file_contains "$REPO_UC/CHANGELOG.md" "0.2.0"
AFTER_SHA=$(git -C "$REPO_UC" rev-list -n1 v0.2.0)
if [[ "$BEFORE_SHA" == "$AFTER_SHA" ]]; then
  ok "update-changelog: existing tag v0.2.0 was not moved"
else
  fail "update-changelog: existing tag v0.2.0 was moved ($BEFORE_SHA -> $AFTER_SHA)"
fi

# skip: clean exit, no changelog write.
REPO_SKIP=$(setup_case "skip")
write_config "$REPO_SKIP" "skip"
if ( cd "$REPO_SKIP" && "$SEMREL_BIN" release --config .semrel.yaml ); then
  ok "skip: semrel release exited 0 (clean skip)"
else
  fail "skip: semrel release exited non-zero, expected a clean skip"
fi

# error: non-zero exit.
REPO_ERROR=$(setup_case "error")
write_config "$REPO_ERROR" "error"
if ( cd "$REPO_ERROR" && "$SEMREL_BIN" release --config .semrel.yaml ); then
  fail "error: semrel release exited 0, expected a non-zero error exit"
else
  ok "error: semrel release exited non-zero, as expected"
fi

finish
