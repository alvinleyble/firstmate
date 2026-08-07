#!/usr/bin/env bash
# Opt-in real-process guard for the agy (Antigravity) Stop hook facts.
#
# Every claim checked here belongs to agy, not to firstmate, so a stub could
# only confirm the assumption already written into the stub. These are the exact
# facts docs/verification/agy.md records and that the whole supervision adapter
# rests on; run this after every agy upgrade and refuse to trust the recorded
# evidence until it passes. tests/fm-agy-hooks.test.sh owns the portable half.
#
# It runs entirely in a scratch HOME so the captain's own ~/.gemini is never
# touched, and it uses agy's non-interactive --print mode so no pty is needed.
set -u

if [ "${FM_AGY_STOP_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_AGY_STOP_LIVE_E2E=1 to run the live agy Stop hook guard"
  exit 0
fi

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AGY_BIN=${FM_AGY_BIN:-$(command -v agy || true)}
[ -n "$AGY_BIN" ] && [ -x "$AGY_BIN" ] ||
  fail "agy not found; set FM_AGY_BIN to an exact executable path"
command -v jq >/dev/null 2>&1 || fail "jq not found"

AGY_VERSION=$("$AGY_BIN" --version 2>&1 | head -1)
echo "# agy version: $AGY_VERSION"

TMP=$(fm_test_tmproot fm-agy-live) || fail "could not create temp root"

# A scratch config root. agy resolves its global customization directory under
# $HOME, so the whole run is isolated by pointing HOME at the fixture.
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.gemini/config"
# Carry over credentials only: without them agy waits on a device-code prompt
# forever rather than exiting, which would read as a hang instead of a skip.
for f in oauth_creds.json google_accounts.json settings.json installation_id; do
  [ -e "$HOME/.gemini/$f" ] && cp -R "$HOME/.gemini/$f" "$FAKE_HOME/.gemini/" 2>/dev/null || true
done
[ -f "$FAKE_HOME/.gemini/oauth_creds.json" ] ||
  echo "# note: no copied credentials; an unauthenticated agy will fail below rather than skip" >&2

WS="$TMP/ws"
fm_git_init_commit "$WS"

LOG="$TMP/hook.log"
COUNT="$TMP/count"

install_hook() {
  local body=$1
  cat > "$FAKE_HOME/.gemini/config/hook.sh" <<EOF
#!/bin/sh
payload=\$(cat)
n=\$(cat "$COUNT" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "$COUNT"
{ echo "--- fire \$n cwd=\$(pwd)"; echo "FM_AGY_LIVE_PROBE=[\${FM_AGY_LIVE_PROBE:-UNSET}]"; echo "\$payload"; } >> "$LOG"
$body
EOF
  chmod +x "$FAKE_HOME/.gemini/config/hook.sh"
  jq -n --arg c "$FAKE_HOME/.gemini/config/hook.sh" \
    '{"fm-live-probe": {Stop: [{type: "command", command: $c, timeout: 120}]}}' \
    > "$FAKE_HOME/.gemini/config/hooks.json"
}

run_agy() {
  ( cd "$WS" && env HOME="$FAKE_HOME" "$@" "$AGY_BIN" --dangerously-skip-permissions \
      --print-timeout 4m -p "Say only the word OK." ) 2>&1
}

# --- 1. the global hooks file is the one that loads -------------------------
: > "$LOG"; rm -f "$COUNT"
install_hook 'echo "{\"decision\":\"allow\"}"'
run_agy >/dev/null || fail "agy run failed; check credentials in the scratch HOME"
[ -s "$COUNT" ] ||
  fail "agy $AGY_VERSION did not fire a Stop hook from the global config; the whole supervision adapter depends on it"
pass "the global hooks.json Stop hook fires"

# --- 2. the launch environment reaches the hook ------------------------------
# This is what firstmate's per-task binding (FM_AGY_TURNEND, FM_AGY_HOOK_ROOT)
# is built on; agy's own payload carries no usable workspace identity.
assert_grep 'FM_AGY_LIVE_PROBE=\[UNSET\]' "$LOG" "the probe should be unset when not passed"
: > "$LOG"; rm -f "$COUNT"
run_agy FM_AGY_LIVE_PROBE=carried >/dev/null || fail "agy run failed"
assert_grep 'FM_AGY_LIVE_PROBE=\[carried\]' "$LOG" \
  "agy must export the launch environment into hook processes"
pass "the launch environment is inherited by the hook"

# --- 3. decision=continue genuinely re-enters the agent loop ----------------
: > "$LOG"; rm -f "$COUNT"
install_hook '
if [ "$n" -le 2 ]; then
  echo "{\"decision\":\"continue\",\"reason\":\"Say the word BANANA, then stop.\"}"
else
  echo "{\"decision\":\"allow\"}"
fi'
out=$(run_agy) || fail "agy run failed"
fires=$(cat "$COUNT" 2>/dev/null || echo 0)
[ "$fires" -ge 3 ] ||
  fail "decision=continue did not re-enter the loop on agy $AGY_VERSION (only $fires stop(s)); firstmate's supervision continuity is broken"
assert_contains "$out" "BANANA" \
  "the continuation reason must be injected so the model acts on the wake text"
pass "decision=continue re-enters the loop and injects the reason"

# --- 4. agy still imposes no continuation ceiling of its own ----------------
# firstmate's budget exists only because of this. If agy ever grows its own
# bound this should be revisited, but a REGRESSION here (a low ceiling) would
# silently cap supervision, so it is worth knowing either way.
: > "$LOG"; rm -f "$COUNT"
install_hook '
if [ "$n" -le 6 ]; then
  echo "{\"decision\":\"continue\",\"reason\":\"Reply with the single word C.\"}"
else
  echo "{\"decision\":\"allow\"}"
fi'
run_agy >/dev/null || true
fires=$(cat "$COUNT" 2>/dev/null || echo 0)
[ "$fires" -ge 7 ] ||
  fail "agy $AGY_VERSION stopped continuing after $fires stops; re-check the continuation budget assumptions in the harness-adapters skill"
pass "agy applies no low continuation ceiling of its own (>=7 observed)"

# --- 5. the effort ceiling is still high ------------------------------------
for bad in xhigh max; do
  if ( cd "$WS" && env HOME="$FAKE_HOME" "$AGY_BIN" --effort "$bad" -p hi ) >/dev/null 2>&1; then
    fail "agy $AGY_VERSION now accepts --effort $bad; update effort_flag_for_harness and the harness-adapters table"
  fi
done
pass "--effort ceiling is still high (xhigh and max rejected)"

# --- 6. model and effort are still a coupled axis ---------------------------
if ( cd "$WS" && env HOME="$FAKE_HOME" "$AGY_BIN" --model gemini-3.1-pro-low --effort high -p hi ) >/dev/null 2>&1; then
  fail "agy $AGY_VERSION no longer rejects an effort-suffixed model alongside --effort; revisit effort_flag_for_harness"
fi
pass "an effort-suffixed model still conflicts with --effort"
