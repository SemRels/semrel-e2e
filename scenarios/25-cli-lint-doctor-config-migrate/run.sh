#!/usr/bin/env bash
# Category coverage: core CLI commands beyond `release`/`workspace release` --
# lint, commitlint, doctor, config (init/show/validate/set), migrate.
# No plugin binaries needed; these are pure semrel-core behavior.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel

REPO=$(new_scenario_repo "25-cli-commands")
echo "# demo" > "$REPO/README.md"
commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0

cat > "$REPO/.semrel.yaml" <<'EOF'
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
  - type: fix
    bump: patch
EOF
git -C "$REPO" add .semrel.yaml
git -C "$REPO" commit -q -m "chore: add semrel config"

# --- lint: a clean history passes ---
if ( cd "$REPO" && "$SEMREL_BIN" lint ); then
  ok "lint: clean conventional-commit history passes"
else
  fail "lint: clean history unexpectedly failed"
fi

# --- lint: a bad commit message fails it ---
echo "x" > "$REPO/bad.txt"
git -C "$REPO" add bad.txt
git -C "$REPO" commit -q -m "this is not a conventional commit"
if ( cd "$REPO" && "$SEMREL_BIN" lint ); then
  fail "lint: a non-conventional commit message was not caught"
else
  ok "lint: a non-conventional commit message is caught"
fi

# --- commitlint: single message argument ---
if ( cd "$REPO" && "$SEMREL_BIN" commitlint "feat(auth): add OAuth2 support" ); then
  ok "commitlint: valid message argument passes"
else
  fail "commitlint: valid message argument unexpectedly failed"
fi
if ( cd "$REPO" && "$SEMREL_BIN" commitlint "not a conventional commit" ); then
  fail "commitlint: invalid message argument was not caught"
else
  ok "commitlint: invalid message argument is caught"
fi

# --- commitlint: stdin ---
if ( cd "$REPO" && echo "fix: typo" | "$SEMREL_BIN" commitlint --stdin ); then
  ok "commitlint: valid message via --stdin passes"
else
  fail "commitlint: valid message via --stdin unexpectedly failed"
fi

# --- doctor: config + git state look sane ---
DOCTOR_OUT=$( cd "$REPO" && "$SEMREL_BIN" doctor 2>&1 )
DOCTOR_RC=$?
echo "$DOCTOR_OUT"
if [[ $DOCTOR_RC -eq 0 ]]; then
  ok "doctor: exits 0 on a valid config + repo"
else
  fail "doctor: exited $DOCTOR_RC on a valid config + repo"
fi

# --- config show / validate ---
if ( cd "$REPO" && "$SEMREL_BIN" config validate ); then
  ok "config validate: accepts the valid config"
else
  fail "config validate: rejected a valid config"
fi
CONFIG_SHOW_OUT=$( cd "$REPO" && "$SEMREL_BIN" config show )
if echo "$CONFIG_SHOW_OUT" | grep -q "tagPrefix"; then
  ok "config show: output includes tagPrefix"
else
  fail "config show: output missing tagPrefix"
fi

# --- config set ---
( cd "$REPO" && "$SEMREL_BIN" config set tagPrefix "rel-" )
assert_file_contains "$REPO/.semrel.yaml" 'tagPrefix: rel-'
( cd "$REPO" && "$SEMREL_BIN" config set tagPrefix "v" )

# --- config init --no-interactive (separate scratch dir) ---
INIT_REPO=$(new_scenario_repo "25-config-init")
if ( cd "$INIT_REPO" && "$SEMREL_BIN" config init --no-interactive ); then
  ok "config init --no-interactive: succeeds"
else
  fail "config init --no-interactive: failed"
fi
assert_file_contains "$INIT_REPO/.semrel.yaml" "schemaVersion"

# --- migrate: already-current config is a no-op ---
BEFORE_HASH=$(git -C "$REPO" hash-object .semrel.yaml)
if ( cd "$REPO" && "$SEMREL_BIN" migrate ); then
  ok "migrate: exits 0 on an already-current config"
else
  fail "migrate: failed on an already-current config"
fi
AFTER_HASH=$(git -C "$REPO" hash-object .semrel.yaml)
if [[ "$BEFORE_HASH" == "$AFTER_HASH" ]]; then
  ok "migrate: left an already-current config unchanged"
else
  fail "migrate: modified a config that was already current"
fi

finish
