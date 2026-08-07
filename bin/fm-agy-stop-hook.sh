#!/usr/bin/env bash
# Firstmate-owned Antigravity (agy) Stop hook.
#
# agy has no per-project hook surface a firstmate launch can rely on: workspace
# .agents/hooks.json did NOT load in agy 1.1.10 (verified), while the global
# ~/.gemini/config/hooks.json loads on every agy session with no trust gate.
# So this is ONE global hook that must be a guarded no-op for every agy session
# that firstmate did not launch, exactly like the grok and kimi global hooks.
#
# The binding is different from grok's, and simpler, because agy exports the
# LAUNCH ENVIRONMENT into the hook process (verified: a variable set on the agy
# command line is readable here). grok had to route through a worktree token
# file because its hook only receives GROK_WORKSPACE_ROOT; agy needs no such
# indirection. Every variable below is still validated for shape before it is
# used, so a stray value from an unrelated session can never make this hook
# write outside a firstmate home.
#
# Two roles, selected by which variable the launch exported:
#
#   FM_AGY_TURNEND=<abs path to state/<id>.turn-ended>
#     CREW role. Touch that marker so the watcher gets a real per-turn wake
#     instead of relying on stale-pane detection, then allow the stop.
#
#   FM_AGY_PRIMARY_HOME=<abs path to a firstmate home>
#     PRIMARY role. Own watcher supervision continuity structurally, so a
#     primary agy session does not depend on the model remembering to re-issue
#     bin/fm-watch-arm.sh after every wake. This is the root cause the agy
#     adapter was hardened to fix.
#
# Why this hook can own supervision at all: agy's Stop hook is SYNCHRONOUS and
# its documented `{"decision":"continue"}` genuinely re-enters the agent loop
# with `reason` injected as a system message (verified end to end). It fires on
# EVERY stop with no model involvement, which is precisely the structural
# property the prompt-level "remember to re-arm" instruction lacked.
#
# The shape that follows from agy's hook being synchronous:
#
#   - A blocking arm (bin/fm-watch-arm.sh) would freeze the agent for as long as
#     the watcher waits, so the primary role runs ONE BOUNDED foreground
#     checkpoint (bin/fm-watch-checkpoint.sh), the same shape codex uses for the
#     same reason. hooks.json must carry a `timeout` larger than that bound;
#     bin/fm-agy-hooks-install.sh writes both together, and a 45s hook under a
#     90s timeout was verified to run to completion rather than being killed at
#     agy's 30s default.
#   - A quiet checkpoint MUST still continue. Returning "allow" on a quiet
#     checkpoint would let the session go idle with work still in flight and no
#     watcher cycle behind it, which is the exact supervision drop this adapter
#     exists to prevent. The continuation reason therefore tells the model to
#     end its turn immediately, so a quiet spin costs one minimal turn per
#     checkpoint period rather than real work.
#   - Continuations MUST be bounded here. agy applies no continuation ceiling of
#     its own: an unconditional "continue" was verified to loop 53+ times with
#     no sign of stopping, so the budget below is the only thing standing
#     between a stuck checkpoint and an infinite agent loop.
#
# stdout is the hook protocol and carries EXACTLY one JSON object. Every
# diagnostic goes to stderr. On any uncertainty this hook allows the stop rather
# than continuing, so a broken guard degrades to today's behavior instead of
# wedging the captain's session.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Always drain stdin: agy writes the Stop payload there and a hook that never
# reads it can leave the writer blocked on a full pipe.
cat >/dev/null 2>&1 || true

# One JSON object on stdout, then exit. jq owns the escaping so an arbitrary
# watcher reason can never produce malformed JSON on the protocol channel.
emit() {
  local decision=$1 reason=${2:-}
  if [ -n "$reason" ] && command -v jq >/dev/null 2>&1; then
    jq -cn --arg d "$decision" --arg r "$reason" '{decision:$d, reason:$r}'
  else
    printf '{"decision":"%s"}\n' "$decision"
  fi
}

allow() { emit allow; exit 0; }

# ---------------------------------------------------------------- crew role
# The marker is created on first touch (every other adapter's turn-end signal
# works the same way), so this cannot require an existing file. It instead pins
# the SHAPE: an absolute path ending in .turn-ended whose parent directory is an
# already-existing directory named `state`. That is firstmate's own state dir
# and nothing else, so a stray or hostile value cannot make this hook create a
# file at an arbitrary location or bring a directory into being.
turnend=${FM_AGY_TURNEND:-}
if [ -n "$turnend" ]; then
  case "$turnend" in
    /*.turn-ended)
      parent=${turnend%/*}
      [ "${parent##*/}" = state ] && [ -d "$parent" ] && touch "$turnend" 2>/dev/null || true
      ;;
  esac
  allow
fi

# ------------------------------------------------------------- primary role
home=${FM_AGY_PRIMARY_HOME:-}
[ -n "$home" ] || allow
case "$home" in /*) : ;; *) allow ;; esac
[ -d "$home" ] || allow

STATE="$home/state"
[ -d "$STATE" ] || allow

# shellcheck source=bin/fm-primary-scope-lib.sh
. "$FM_ROOT/bin/fm-primary-scope-lib.sh" 2>/dev/null || allow
# shellcheck source=bin/fm-supervision-lib.sh
. "$FM_ROOT/bin/fm-supervision-lib.sh" 2>/dev/null || allow

# The same scope predicate the turn-end guard and the claude auto-arm use: a
# genuine primary checkout, never a crew or scout worktree.
fm_primary_scope_matches "$home" "$STATE" || allow

# While away mode is active the sub-supervisor daemon owns supervision and
# triage. Arming here too would create the second cycle AGENTS.md section 8
# forbids.
[ -e "$STATE/.afk" ] && allow

BUDGET_FILE="$STATE/.agy-autoarm-blocks"
MAX_BLOCKS=${FM_AGY_STOP_MAX_BLOCKS:-60}
CHECKPOINT=${FM_AGY_STOP_CHECKPOINT:-240}

case "$MAX_BLOCKS" in ''|*[!0-9]*) MAX_BLOCKS=60 ;; esac
case "$CHECKPOINT" in ''|*[!0-9]*) CHECKPOINT=240 ;; esac

read_budget() {
  local n
  n=$(cat "$BUDGET_FILE" 2>/dev/null) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# An idle home needs no supervision, so clear the budget and let the session
# rest. This is also the normal way a spin loop ends: work lands, supervision is
# no longer needed, and the next stop is allowed.
if ! fm_supervision_needed "$STATE"; then
  rm -f "$BUDGET_FILE" 2>/dev/null || true
  allow
fi

blocks=$(read_budget)
if [ "$blocks" -ge "$MAX_BLOCKS" ]; then
  echo "fm-agy-stop-hook: continuation budget ($MAX_BLOCKS) exhausted with supervision still needed; allowing the stop so the session does not loop. Re-arm supervision manually and investigate the watcher." >&2
  rm -f "$BUDGET_FILE" 2>/dev/null || true
  allow
fi

# One bounded foreground checkpoint. Exit 0 carries an actionable wake, 124 is a
# quiet checkpoint, anything else is a genuine failure worth surfacing.
#
# FM_HOME is exported explicitly rather than inherited: bin/fm-watch.sh resolves
# its state dir from FM_HOME and falls back to its OWN checkout root, so a
# secondmate home's hook would otherwise supervise the wrong home.
out=$(FM_HOME="$home" "$FM_ROOT/bin/fm-watch-checkpoint.sh" --seconds "$CHECKPOINT" 2>/dev/null)
rc=$?

if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
  rm -f "$BUDGET_FILE" 2>/dev/null || true
  emit continue "Firstmate supervision wake (delivered by the Antigravity Stop hook, not by you re-arming anything).

$out

Drain the durable wake queue with bin/fm-wake.sh drain BEFORE anything else, then handle this wake per AGENTS.md section 8. Do not run bin/fm-watch-arm.sh: this hook owns the next supervision cycle and will run it when your turn ends."
  exit 0
fi

printf '%s\n' "$((blocks + 1))" > "$BUDGET_FILE" 2>/dev/null || true

if [ "$rc" -eq 124 ]; then
  emit continue "Firstmate supervision checkpoint completed with no actionable wake, and work is still in flight. Nothing needs doing. End your turn immediately without tool calls or commentary so the next supervision checkpoint can start."
  exit 0
fi

emit continue "Firstmate supervision checkpoint failed (exit $rc). Investigate the watcher per AGENTS.md section 8 before continuing other work; do not treat this as a routine wake."
exit 0
