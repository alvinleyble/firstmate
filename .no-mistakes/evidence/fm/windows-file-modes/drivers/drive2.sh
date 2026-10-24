#!/usr/bin/env bash
# drive2.sh <scratch>: merge with an LF jq, then teardown, on the lab homes drive.sh left.
set -u
SCRATCH=$1
WT=/c/Users/amfne/.no-mistakes/worktrees/efaf735780a2/01M5NK0KCFYG02X2CBAAME90JF
BASE="$SCRATCH/base"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
umask 022
mode() { stat -c %a "$1"; }
show_state() { (cd "$1" && for f in $(ls -A | LC_ALL=C sort); do [ -f "$f" ] && printf '    %-42s mode(read)=%s links=%s\n' "$f" "$(mode "$f")" "$(stat -c %h "$f")"; done); }
run() { local desc=$1 rc; shift; echo "\$ $desc"; "$@" > "$SCRATCH/.out" 2> "$SCRATCH/.err"; rc=$?
  sed 's/^/    stdout: /' "$SCRATCH/.out"; grep -v '^●\|WARNING: watcher still down' "$SCRATCH/.err" | sed 's/^/    stderr: /'; echo "    exit=$rc"; return $rc; }
for LABEL in base target; do
  if [ "$LABEL" = base ]; then ROOT=$BASE; else ROOT=$WT; fi
  dir=$(cat "$SCRATCH/$LABEL/prflow-dir")
  export FM_TEST_GUARD_LOG="$dir/guard.log" FM_TEST_GH_LOG="$dir/gh.log" FM_TEST_GH_AXI_LOG="$dir/gh-axi.log" \
    FM_TEST_GLAB_LOG="$dir/glab.log" FM_TEST_GERRIT_AXI_LOG="$dir/gerrit-axi.log"
  echo "=== [$LABEL] S3 merge with LF jq (PATH=<fake gh>:<jq -b shim>:\$PATH)"
  : > "$dir/gh.log"
  run "FM_HOME=<lab> bin/fm-pr-merge.sh task-a https://github.com/o/r/pull/1" \
    env FM_HOME="$dir/home" PATH="$dir/fakebin:$SCRATCH/jqlf:$PATH" "$ROOT/bin/fm-pr-merge.sh" task-a https://github.com/o/r/pull/1
  echo "  forge merge calls: $(grep '^pr merge' "$dir/gh.log" | tr '\n' ' ')"
  [ -f "$dir/home/state/task-a.merge-authority" ] && { echo "  task-a.merge-authority:"; sed 's/^/      /' "$dir/home/state/task-a.merge-authority"; }
  show_state "$dir/home/state"
  echo
done
