#!/usr/bin/env bash
# E2E: Agent B sees only NEW findings through `blaze radar sync` after baseline.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLAZE="$ROOT/.build/debug/blaze-radar-demo"
DAEMON="$ROOT/.build/debug/blaze-radar-demo-daemon"
SOCK="/tmp/blaze_radar.sock"

PASS=0
fail() { echo "FAIL: $1"; exit 1; }
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }

assert_contains() {
  echo "$1" | grep -Fq "$2" && pass "$3" || { echo "$1"; fail "$3"; }
}
assert_not_contains() {
  echo "$1" | grep -Fq "$2" && fail "$3 (unexpected: $2)" || pass "$3"
}

cleanup() {
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null || true
}
trap cleanup EXIT

swift build -q
TEST_DIR="$(mktemp -d)"
cd "$TEST_DIR" && git init -q && git config user.email t@t && git config user.name T
echo hi > README.md && git add . && git commit -q -m init
WORKSPACE="$TEST_DIR"
git branch -q fix/a && git branch -q fix/b
git worktree add -q "$TEST_DIR/wt-a" fix/a
git worktree add -q "$TEST_DIR/wt-b" fix/b

rm -f "$SOCK"
"$DAEMON" & DAEMON_PID=$!
for i in {1..30}; do [[ -S "$SOCK" ]] && break; sleep 0.1; done
[[ -S "$SOCK" ]] || fail "daemon not ready"
[[ -f "$TEST_DIR/wt-a/.blaze/radar/radar.blazedb" ]] && fail "board must not live in worktree checkout" || true
[[ -f "$TEST_DIR/wt-b/.blaze/radar/radar.blazedb" ]] && fail "board must not live in worktree checkout" || true

F1="Found: missing attention arbiter, don't build another scheduler"
F2="Found: attention slot already claimed by signup flow"

"$BLAZE" radar register "fix prompt scheduler" --workspace "$WORKSPACE" --worktree "$TEST_DIR/wt-a" --agent agent-a --branch fix/a >/dev/null
"$BLAZE" radar update --found "$F1" --workspace "$WORKSPACE" --agent agent-a >/dev/null

"$BLAZE" radar register "fix signup interruptions" --workspace "$WORKSPACE" --worktree "$TEST_DIR/wt-b" --agent agent-b --branch fix/b >/dev/null
BASE=$("$BLAZE" radar sync --workspace "$WORKSPACE" --agent agent-b)
assert_contains "$BASE" "first sync" "baseline captured"
assert_contains "$BASE" "$F1" "finding one in ACTIVE"
assert_not_contains "$BASE" "+ $F1" "finding one not in NEW delta"

"$BLAZE" radar update --found "$F2" --workspace "$WORKSPACE" --agent agent-a >/dev/null
DELTA=$("$BLAZE" radar sync --workspace "$WORKSPACE" --agent agent-b)
assert_contains "$DELTA" "+ $F2" "only finding two is new"
assert_not_contains "$DELTA" "+ $F1" "finding one not repeated"

echo "All $PASS checks passed"
