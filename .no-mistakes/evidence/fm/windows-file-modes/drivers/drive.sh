#!/usr/bin/env bash
# drive.sh <root-label> <root-dir> <scratch>
# Runs the real firstmate entrypoints from <root-dir> against a fresh marked lab
# home on this Windows (Git Bash, noacl) drive. Only the forge CLIs (gh,
# no-mistakes) and tmux are fakes, copied verbatim from the repo's own suite.
set -u
LABEL=$1 ROOT=$2 SCRATCH=$3
WT=/c/Users/amfne/.no-mistakes/worktrees/efaf735780a2/01M5NK0KCFYG02X2CBAAME90JF
. "$SCRATCH/tools/make_case.sh"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
umask 022
TMP_ROOT="$SCRATCH/$LABEL"
mkdir -p "$TMP_ROOT"
mode() { stat -c %a "$1"; }
show_state() { (cd "$1" && for f in $(ls -A | LC_ALL=C sort); do [ -f "$f" ] && printf '    %-42s mode(read)=%s links=%s\n' "$f" "$(mode "$f")" "$(stat -c %h "$f")"; done); }
run() { # <desc> <cmd...>
  local desc=$1 rc; shift
  echo "\$ $desc"
  "$@" > "$TMP_ROOT/.out" 2> "$TMP_ROOT/.err"; rc=$?
  sed 's/^/    stdout: /' "$TMP_ROOT/.out"; sed 's/^/    stderr: /' "$TMP_ROOT/.err"
  echo "    exit=$rc"
  return $rc
}
echo "=== [$LABEL] root=$ROOT  OSTYPE=$OSTYPE umask=$(umask) commit=$( [ "$LABEL" = target ] && git -C "$WT" rev-parse --short HEAD || echo 597c675)"
echo

echo "--- S1 contribution observation arm (what bootstrap and fm-pr-check call) ---"
LAB="$TMP_ROOT/contrib-home"
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
run "FM_HOME=<lab> bin/fm-contributions.sh arm" env FM_HOME="$LAB" "$ROOT/bin/fm-contributions.sh" arm
show_state "$LAB/state"
echo

echo "--- S2/S3 PR-ready recording then merge for task-a ---"
dir=$(make_case prflow)
rm -rf "$dir/home"
"$WT/bin/fm-lab-home.sh" create "$dir/home" >/dev/null
write_task_meta "$dir" task-a
export FM_TEST_GUARD_LOG="$dir/guard.log" FM_TEST_GH_LOG="$dir/gh.log" FM_TEST_GH_AXI_LOG="$dir/gh-axi.log" \
  FM_TEST_GLAB_LOG="$dir/glab.log" FM_TEST_GERRIT_AXI_LOG="$dir/gerrit-axi.log"
run "FM_HOME=<lab> bin/fm-pr-check.sh task-a https://github.com/o/r/pull/1" \
  env FM_HOME="$dir/home" PATH="$dir/fakebin:$PATH" "$ROOT/bin/fm-pr-check.sh" task-a https://github.com/o/r/pull/1
echo "  task-a.meta pr lines: $(grep -E '^pr(_head)?=' "$dir/home/state/task-a.meta" | tr '\n' ' ')"
run "FM_HOME=<lab> bin/fm-pr-merge.sh task-a https://github.com/o/r/pull/1" \
  env FM_HOME="$dir/home" PATH="$dir/fakebin:$PATH" "$ROOT/bin/fm-pr-merge.sh" task-a https://github.com/o/r/pull/1
echo "  forge merge calls: $(grep '^pr merge' "$dir/gh.log" | tr '\n' ' ')"
show_state "$dir/home/state"
cp -a "$dir/home" "$TMP_ROOT/home-after-merge"
echo "$dir" > "$TMP_ROOT/prflow-dir"
echo
