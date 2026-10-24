#!/usr/bin/env bash
# drive3.sh <scratch>: teardown of the merged task-a home (base vs target).
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
dir=$(cat "$SCRATCH/target/prflow-dir")
printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/fakebin/tmux"; chmod 0700 "$dir/fakebin/tmux"
rm -rf "$dir/wt"
touch "$dir/home/state/.last-watcher-beat"
rm -rf "$SCRATCH/teardown-base"; mkdir -p "$SCRATCH/teardown-base"
cp -a "$dir/home" "$SCRATCH/teardown-base/home"
for LABEL in base target; do
  if [ "$LABEL" = base ]; then ROOT=$BASE; HOME_DIR="$SCRATCH/teardown-base/home"; else ROOT=$WT; HOME_DIR="$dir/home"; fi
  echo "=== [$LABEL] S4 teardown of merged task-a (state holds task-a.merge-authority, read mode $(mode "$HOME_DIR/state/task-a.merge-authority"))"
  run "FM_HOME=<lab> bin/fm-teardown.sh task-a --force" \
    env FM_HOME="$HOME_DIR" PATH="$dir/fakebin:$PATH" "$ROOT/bin/fm-teardown.sh" task-a --force
  echo "  remaining task-a artifacts: $(cd "$HOME_DIR/state" && ls -A | grep '^task-a\.' | tr '\n' ' ')"
  echo
done
