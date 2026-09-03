#!/usr/bin/env bash
# common.sh - shared helpers sourced by every scenarios/*/run.sh
#
# A scenario script does:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/common.sh"
#   build_semrel
#   PLUGIN=$(build_plugin <repo-dir-name> <short-name>)
#   REPO=$(new_scenario_repo "$(basename "$(dirname "${BASH_SOURCE[0]}")")")
#   ... seed commits, write .semrel.yaml, run "$SEMREL_BIN" ...
#   assert_* ...
#   finish

set -euo pipefail

SCRIPT_DIR_COMMON="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
E2E_ROOT="$(cd -- "$SCRIPT_DIR_COMMON/.." && pwd)"
WORKSPACE_ROOT="$(cd -- "$E2E_ROOT/.." && pwd)"
SEMREL_SRC="$WORKSPACE_ROOT/semrel"

BIN_DIR="$E2E_ROOT/.bin"
SEMREL_BIN="$BIN_DIR/semrel"
PLUGIN_BIN_DIR="$E2E_ROOT/.bin/plugins"
WORK_DIR="${SEMREL_E2E_WORKDIR:-$E2E_ROOT/.work}"

SCENARIO_FAILED=0
PASS_COUNT=0
FAIL_COUNT=0

# --- build helpers ---------------------------------------------------------

build_semrel() {
  if [[ -x "$SEMREL_BIN" && "${SEMREL_E2E_REBUILD:-0}" != "1" ]]; then
    return 0
  fi
  mkdir -p "$BIN_DIR"
  VERSION="$(git -C "$SEMREL_SRC" describe --tags --always --dirty 2>/dev/null || echo dev)"
  go -C "$SEMREL_SRC" build -trimpath -ldflags "-X github.com/SemRels/semrel/internal/cli.version=$VERSION" -o "$SEMREL_BIN" ./cmd/semrel
}

# Windows note: Go's exec.LookPath refuses to run an absolute path unless the
# file has an extension listed in PATHEXT, even though the file itself is a
# valid PE binary -- so plugin binaries must be built as *.exe here, and
# SEMREL_BIN below likewise.
BIN_EXT=""
case "$(go env GOOS 2>/dev/null || echo "")" in
  windows) BIN_EXT=".exe" ;;
esac
SEMREL_BIN="$SEMREL_BIN$BIN_EXT"

# native_path <posix-path> -> the same path in the OS's own notation.
# On Windows/MSYS, semrel.exe and the plugin *.exe are native binaries that
# call CreateProcess directly: an MSYS-style path like /c/Users/... isn't
# resolvable to them, only C:\Users\... is. Elsewhere this is a no-op.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    # -m: drive-letter path with forward slashes (C:/Users/...) -- Windows
    # accepts this for CreateProcess, and it drops safely into YAML double-
    # quoted strings without backslash-escaping headaches.
    cygpath -m "$1"
  else
    echo "$1"
  fi
}

# build_plugin <repo-dir-name> <short-name> -> prints the built binary's
# native (OS-notation) path, ready to drop straight into a `path:` field.
build_plugin() {
  local repo="$1" name="$2"
  local out="$PLUGIN_BIN_DIR/semrel-plugin-$name$BIN_EXT"
  if [[ -x "$out" && "${SEMREL_E2E_REBUILD:-0}" != "1" ]]; then
    native_path "$out"
    return 0
  fi
  mkdir -p "$PLUGIN_BIN_DIR"
  local repo_dir="$WORKSPACE_ROOT/$repo"
  if [[ ! -f "$repo_dir/cmd/plugin/main.go" ]]; then
    echo "missing plugin repository or entrypoint: $repo_dir/cmd/plugin/main.go" >&2
    exit 1
  fi
  go -C "$repo_dir" build -trimpath -o "$out" ./cmd/plugin >&2
  native_path "$out"
}

# --- fixture repo helpers ---------------------------------------------------

# new_scenario_repo <name> -> prints absolute path to a fresh git repo under .work/
new_scenario_repo() {
  local name="$1"
  local dir="$WORK_DIR/$name"
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email e2e@semrel.local
  git -C "$dir" config user.name "semrel e2e"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config tag.gpgsign false
  echo "$dir"
}

commit_all() {
  local repo="$1" msg="$2"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$msg"
}

# --- assertions --------------------------------------------------------------

ok()   { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); SCENARIO_FAILED=1; }

# skip <reason> - marks the scenario skipped (not failed) and exits immediately.
# Convention: exit code 77 means "skipped", read by scripts/run-all.sh.
skip() {
  echo "  [SKIP] $1"
  exit 77
}

# require_env VAR1 VAR2 ... - skip the scenario if any listed env var is unset/empty.
# Used to gate scenarios that talk to real external services (GitHub, Slack, ...).
require_env() {
  local var
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      skip "requires env var $var (external/opt-in scenario, see scenario README)"
    fi
  done
}

# require_cmd CMD - skip the scenario if a required external tool isn't installed.
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    skip "requires '$cmd' on PATH (not installed)"
  fi
}

assert_file_contains() {
  local file="$1" pattern="$2"
  if [[ -f "$file" ]] && grep -q -- "$pattern" "$file" 2>/dev/null; then
    ok "$file contains: $pattern"
  else
    fail "$file does NOT contain: $pattern"
  fi
}

assert_file_not_contains() {
  local file="$1" pattern="$2"
  if [[ -f "$file" ]] && grep -q -- "$pattern" "$file" 2>/dev/null; then
    fail "$file unexpectedly contains: $pattern"
  else
    ok "$file does not contain: $pattern"
  fi
}

assert_tag_exists() {
  local repo="$1" tag="$2"
  if git -C "$repo" tag --list "$tag" | grep -qx -- "$tag"; then
    ok "tag $tag exists"
  else
    fail "tag $tag missing (found: $(git -C "$repo" tag --list | tr '\n' ' '))"
  fi
}

assert_tag_absent() {
  local repo="$1" tag="$2"
  if git -C "$repo" tag --list "$tag" | grep -qx -- "$tag"; then
    fail "tag $tag exists but release should have been blocked"
  else
    ok "tag $tag absent, as expected"
  fi
}

# --- local mock HTTP endpoint (for publisher/hook scenarios) ---------------
# Avoids ever contacting a real external service: scenarios that need "some
# HTTP endpoint" point plugins at this instead of Slack/GitHub/etc.

MOCK_SERVER_PID=""
MOCK_SERVER_LOG=""

# start_mock_server <requests-log-path> -> prints "http://127.0.0.1:<port>"
start_mock_server() {
  require_cmd node
  MOCK_SERVER_LOG="$1"
  : > "$MOCK_SERVER_LOG"
  local out
  out="$(mktemp)"
  node "$E2E_ROOT/scripts/mock-http-server/server.js" 0 "$MOCK_SERVER_LOG" >"$out" 2>&1 &
  MOCK_SERVER_PID=$!
  local port=""
  for _ in $(seq 1 50); do
    if [[ -s "$out" ]] && grep -q "^LISTENING " "$out"; then
      port="$(grep "^LISTENING " "$out" | head -1 | awk '{print $2}')"
      break
    fi
    sleep 0.1
  done
  rm -f "$out"
  if [[ -z "$port" ]]; then
    fail "mock HTTP server did not start"
    echo ""
    return 1
  fi
  echo "http://127.0.0.1:$port"
}

stop_mock_server() {
  [[ -n "$MOCK_SERVER_PID" ]] && kill "$MOCK_SERVER_PID" >/dev/null 2>&1 || true
}

MOCK_SMTP_PID=""

# start_mock_smtp_server <messages-log-path> -> prints the port it's listening on
start_mock_smtp_server() {
  require_cmd node
  local log="$1"
  : > "$log"
  local out
  out="$(mktemp)"
  node "$E2E_ROOT/scripts/mock-smtp-server/server.js" 0 "$log" >"$out" 2>&1 &
  MOCK_SMTP_PID=$!
  local port=""
  for _ in $(seq 1 50); do
    if [[ -s "$out" ]] && grep -q "^LISTENING " "$out"; then
      port="$(grep "^LISTENING " "$out" | head -1 | awk '{print $2}')"
      break
    fi
    sleep 0.1
  done
  rm -f "$out"
  if [[ -z "$port" ]]; then
    fail "mock SMTP server did not start"
    echo ""
    return 1
  fi
  echo "$port"
}

stop_mock_smtp_server() {
  [[ -n "$MOCK_SMTP_PID" ]] && kill "$MOCK_SMTP_PID" >/dev/null 2>&1 || true
}

# --- local OCI registry (for publisher-oci) -----------------------------
# A real, pure-Go OCI Distribution server (github.com/distribution/distribution
# cmd/registry) -- not a mock. Install with:
#   go install github.com/distribution/distribution/v3/cmd/registry@latest

REGISTRY_PID=""

# start_local_registry <storage-dir> -> prints "127.0.0.1:<port>"
start_local_registry() {
  require_cmd registry
  local storage_dir="$1"
  mkdir -p "$storage_dir"
  local config
  config="$(mktemp)"
  local port
  port=$(( (RANDOM % 20000) + 20000 ))
  cat > "$config" <<EOF
version: 0.1
log:
  level: error
storage:
  filesystem:
    rootdirectory: $(native_path "$storage_dir")
http:
  addr: 127.0.0.1:$port
EOF
  registry serve "$config" >"$storage_dir/../registry.log" 2>&1 &
  REGISTRY_PID=$!
  local ready=""
  for _ in $(seq 1 50); do
    if curl -s -o /dev/null "http://127.0.0.1:$port/v2/"; then
      ready=1
      break
    fi
    sleep 0.1
  done
  if [[ -z "$ready" ]]; then
    fail "local OCI registry did not start"
    echo ""
    return 1
  fi
  echo "127.0.0.1:$port"
}

stop_local_registry() {
  [[ -n "$REGISTRY_PID" ]] && kill "$REGISTRY_PID" >/dev/null 2>&1 || true
}

# finish - print scenario summary and exit non-zero if any assertion failed.
finish() {
  stop_mock_server
  stop_mock_smtp_server
  stop_local_registry
  if [[ "$SCENARIO_FAILED" != "0" ]]; then
    echo "  -> scenario FAILED ($FAIL_COUNT failed, $PASS_COUNT passed)"
    exit 1
  fi
  echo "  -> scenario OK ($PASS_COUNT passed)"
  exit 0
}
