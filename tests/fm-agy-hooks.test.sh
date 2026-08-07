#!/usr/bin/env bash
# shellcheck disable=SC1091
# Behavior tests for firstmate's agy (Antigravity) hook adapter.
#
# Scope split, deliberately:
#   - The facts that come from agy ITSELF (that a Stop hook fires at all, that
#     {"decision":"continue"} re-enters the loop, that the launch environment
#     reaches the hook, that hooks load only from the global config) are
#     harness-dependent and cannot be proven by a stub. They are proven live in
#     docs/verification/agy.md and re-checked by the live-harness guard there.
#   - THIS suite pins the logic firstmate owns on top of those facts: the guard
#     that keeps one global hook inert for sessions firstmate did not launch,
#     the continuation budget that is the only bound on agy's unlimited Stop
#     continuations, and the installer's single-key ownership of a shared file.
# Those run with no agy binary present, so CI enforces them everywhere.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$ROOT/bin/fm-agy-stop-hook.sh"
INSTALL="$ROOT/bin/fm-agy-hooks-install.sh"

TMP=$(fm_test_tmproot fm-agy) || fail "could not create temp root"

# A hook run always receives a Stop payload on stdin and must answer with one
# JSON object on stdout.
run_hook() {
  printf '{"executionNum":0,"terminationReason":"NO_TOOL_CALL","fullyIdle":true}' |
    env "$@" "$HOOK" 2>/dev/null
}

decision_of() {
  printf '%s' "$1" | sed -n 's/.*"decision":"\([a-z_]*\)".*/\1/p'
}

# --- a primary home fixture -------------------------------------------------
# fm_primary_scope_matches requires a plain checkout (git-dir == git-common-dir)
# carrying AGENTS.md, bin/, and the state dir.
HOME_OK="$TMP/home"
fm_git_init_commit "$HOME_OK"
printf '# fixture\n' > "$HOME_OK/AGENTS.md"
mkdir -p "$HOME_OK/bin" "$HOME_OK/state"

# Supervision is "needed" exactly while a task meta is present.
fm_write_meta "$HOME_OK/state/task1.meta" 'window=fake:0' 'harness=agy' 'kind=ship'

# A stub checkout whose checkpoint is deterministic, so the budget behavior is
# tested without waiting on the real watcher. FM_ROOT_OVERRIDE is the hook's own
# documented root override.
STUB="$TMP/stub"
mkdir -p "$STUB/bin"
cp "$ROOT/bin/fm-primary-scope-lib.sh" "$ROOT/bin/fm-supervision-lib.sh" "$STUB/bin/"
stub_checkpoint() {
  cat > "$STUB/bin/fm-watch-checkpoint.sh" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "$STUB/bin/fm-watch-checkpoint.sh"
}
stub_checkpoint 'exit 124'

hook_in_stub() {
  run_hook FM_ROOT_OVERRIDE="$STUB" "$@"
}

# --- guard: inert unless firstmate launched the session ---------------------

out=$(run_hook FM_AGY_NOTHING=1)
[ "$(decision_of "$out")" = allow ] ||
  fail "a session with no firstmate variables must be allowed to stop, got: $out"
pass "no firstmate environment leaves the shared global hook inert"

for bad in "../etc" "relative/path" "$TMP/does-not-exist"; do
  out=$(hook_in_stub FM_AGY_PRIMARY_HOME="$bad")
  [ "$(decision_of "$out")" = allow ] ||
    fail "a non-absolute or missing primary home must be allowed to stop: $bad"
done
pass "a malformed or missing primary home never continues the loop"

out=$(hook_in_stub FM_AGY_PRIMARY_HOME="$TMP")
[ "$(decision_of "$out")" = allow ] ||
  fail "a directory that is not a primary firstmate home must be allowed to stop"
pass "a directory outside primary scope never continues the loop"

# --- crew role: the turn-end marker ----------------------------------------

MARK="$HOME_OK/state/task1.turn-ended"
assert_absent "$MARK" "the marker should not exist before the first turn ends"
out=$(run_hook FM_AGY_TURNEND="$MARK")
[ "$(decision_of "$out")" = allow ] || fail "the crew role must always allow the stop"
assert_present "$MARK" "the crew role must create the turn-end marker on first fire"
pass "the crew role signals a turn boundary through the state marker"

# The marker path is attacker-shaped input, so its SHAPE is the whole guard: an
# absolute .turn-ended path whose parent is an existing directory named state.
for bad in "$TMP/evil.txt" "$TMP/evil.turn-ended" "relative.turn-ended"; do
  run_hook FM_AGY_TURNEND="$bad" >/dev/null
  assert_absent "$bad" "the crew role must refuse to create $bad"
done
pass "the crew role writes only inside a real state directory"

# --- primary role: continuation and its bound -------------------------------

rm -f "$HOME_OK/state/.agy-autoarm-blocks"
out=$(hook_in_stub FM_AGY_PRIMARY_HOME="$HOME_OK")
[ "$(decision_of "$out")" = continue ] ||
  fail "a quiet checkpoint with work in flight must continue, not allow: $out"
assert_contains "$out" "End your turn immediately" \
  "a quiet continuation must tell the model to spend nothing on it"
pass "a quiet checkpoint keeps supervision alive instead of going idle"

# agy imposes NO ceiling of its own on Stop continuations (verified live: 53+
# with no sign of stopping), so this budget is the only thing between a stuck
# checkpoint and an infinite agent loop. This is the single most important
# assertion in the file.
rm -f "$HOME_OK/state/.agy-autoarm-blocks"
seen_allow=
for _ in 1 2 3 4 5 6 7 8; do
  out=$(hook_in_stub FM_AGY_PRIMARY_HOME="$HOME_OK" FM_AGY_STOP_MAX_BLOCKS=3)
  [ "$(decision_of "$out")" = allow ] && { seen_allow=1; break; }
done
[ -n "$seen_allow" ] ||
  fail "the continuation budget must eventually allow the stop; agy will not stop the loop for us"
pass "the continuation budget bounds an otherwise unlimited Stop loop"

# An actionable wake resets the budget, so a busy fleet is never starved by
# earlier quiet checkpoints.
stub_checkpoint 'echo "signal: task1 needs attention"; exit 0'
printf '2\n' > "$HOME_OK/state/.agy-autoarm-blocks"
out=$(hook_in_stub FM_AGY_PRIMARY_HOME="$HOME_OK")
[ "$(decision_of "$out")" = continue ] || fail "an actionable wake must continue: $out"
assert_contains "$out" "signal: task1 needs attention" \
  "the wake text must reach the model in the continuation reason"
assert_absent "$HOME_OK/state/.agy-autoarm-blocks" \
  "an actionable wake must reset the continuation budget"
pass "an actionable wake is delivered and clears the budget"

# --- primary role: it must never compete with other owners ------------------

stub_checkpoint 'exit 124'
touch "$HOME_OK/state/.afk"
out=$(hook_in_stub FM_AGY_PRIMARY_HOME="$HOME_OK")
[ "$(decision_of "$out")" = allow ] ||
  fail "away mode owns supervision; the hook must not arm a second cycle"
rm -f "$HOME_OK/state/.afk"
pass "away mode keeps the hook inert"

mv "$HOME_OK/state/task1.meta" "$TMP/task1.meta.bak"
printf '4\n' > "$HOME_OK/state/.agy-autoarm-blocks"
out=$(hook_in_stub FM_AGY_PRIMARY_HOME="$HOME_OK")
[ "$(decision_of "$out")" = allow ] || fail "an idle home must be allowed to stop: $out"
assert_absent "$HOME_OK/state/.agy-autoarm-blocks" \
  "an idle home must clear the continuation budget"
mv "$TMP/task1.meta.bak" "$HOME_OK/state/task1.meta"
pass "an idle home stops cleanly and resets the budget"

# --- installer: it edits a file the captain also owns -----------------------

if command -v jq >/dev/null 2>&1; then
  CFG="$TMP/gemini-config"
  mkdir -p "$CFG"
  cat > "$CFG/hooks.json" <<'EOF'
{"captains-own-hook": {"PostToolUse": [{"matcher": "run_command", "hooks": [{"command": "echo hi"}]}]}}
EOF
  FM_AGY_CONFIG_DIR="$CFG" "$INSTALL" install --timeout 300 >/dev/null ||
    fail "install should succeed against a valid hooks file"
  jq -e '.["captains-own-hook"].PostToolUse[0].hooks[0].command == "echo hi"' "$CFG/hooks.json" >/dev/null ||
    fail "install must not disturb hook entries firstmate does not own"
  jq -e '.["firstmate-turn-end"].Stop[0].timeout == 300' "$CFG/hooks.json" >/dev/null ||
    fail "install must record the requested timeout"
  pass "install owns exactly one key and preserves the captain's own hooks"

  FM_AGY_CONFIG_DIR="$CFG" "$INSTALL" install >/dev/null ||
    fail "install must be idempotent"
  [ "$(jq -r 'keys | length' "$CFG/hooks.json")" = 2 ] ||
    fail "a second install must not add another key"
  pass "install is idempotent"

  # The registered command is a shim, so one global file stays correct no matter
  # which checkout installed it last.
  shim=$(jq -r '.["firstmate-turn-end"].Stop[0].command' "$CFG/hooks.json")
  [ -x "$shim" ] || fail "the registered hook command must exist and be executable"
  out=$(printf '{}' | "$shim")
  [ "$(decision_of "$out")" = allow ] ||
    fail "the shim must be inert with no FM_AGY_HOOK_ROOT, got: $out"
  out=$(printf '{}' | FM_AGY_HOOK_ROOT="$TMP/nope" "$shim")
  [ "$(decision_of "$out")" = allow ] ||
    fail "the shim must be inert for a hook root that has no hook, got: $out"
  pass "the installed shim is inert without a valid firstmate hook root"

  FM_AGY_CONFIG_DIR="$CFG" "$INSTALL" status >/dev/null || fail "status should report installed"
  FM_AGY_CONFIG_DIR="$CFG" "$INSTALL" remove >/dev/null || fail "remove should succeed"
  jq -e 'has("firstmate-turn-end") | not' "$CFG/hooks.json" >/dev/null ||
    fail "remove must delete firstmate's key"
  jq -e 'has("captains-own-hook")' "$CFG/hooks.json" >/dev/null ||
    fail "remove must leave the captain's own hooks in place"
  FM_AGY_CONFIG_DIR="$CFG" "$INSTALL" status >/dev/null 2>&1 &&
    fail "status must exit non-zero once the hook is removed"
  pass "remove withdraws only firstmate's key and status tracks it"

  printf 'not json at all\n' > "$CFG/hooks.json"
  FM_AGY_CONFIG_DIR="$CFG" "$INSTALL" install >/dev/null 2>&1 &&
    fail "install must refuse a corrupt hooks file rather than replacing it"
  assert_grep 'not json at all' "$CFG/hooks.json" \
    "a refused install must leave the existing file untouched"
  pass "install refuses to overwrite a hooks file it cannot parse"
else
  pass "installer checks skipped: jq is not installed"
fi
