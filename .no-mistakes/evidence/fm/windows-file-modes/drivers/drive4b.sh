#!/usr/bin/env bash
set -u
SCRATCH=$1
WT=/c/Users/amfne/.no-mistakes/worktrees/efaf735780a2/01M5NK0KCFYG02X2CBAAME90JF
BASE="$SCRATCH/base"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
umask 022
run() { local desc=$1 rc; shift; echo "\$ $desc"; "$@" > "$SCRATCH/.out" 2> "$SCRATCH/.err"; rc=$?
  sed 's/^/    stdout: /' "$SCRATCH/.out"; sed 's/^/    stderr: /' "$SCRATCH/.err"; echo "    exit=$rc"; return $rc; }
ident() { [ -f "$1" ] && printf 'fileid=%s mtime_ns=%s mode(read)=%s' "$(stat -c %i "$1")" "$(stat -c %.9Y "$1")" "$(stat -c %a "$1")" || printf 'absent'; }
for LABEL in base target; do
  if [ "$LABEL" = base ]; then ROOT=$BASE; else ROOT=$WT; fi
  LAB="$SCRATCH/$LABEL/shim-home"
  cp "$WT/docs/examples/watched-tools.json" "$LAB/config/watched-tools.json"
  echo "=== [$LABEL] S5 tool-update check shim (config/watched-tools.json copied from docs/examples)"
  shim="$LAB/state/tool-updates.check.sh"
  run "FM_HOME=<lab> bin/fm-tool-update-check.sh arm   (first)" env FM_HOME="$LAB" "$ROOT/bin/fm-tool-update-check.sh" arm
  first=$(ident "$shim"); echo "    shim after first arm:  $first"
  sleep 1.1
  run "FM_HOME=<lab> bin/fm-tool-update-check.sh arm   (again)" env FM_HOME="$LAB" "$ROOT/bin/fm-tool-update-check.sh" arm
  second=$(ident "$shim"); echo "    shim after second arm: $second"
  if [ "$first" != absent ] && [ "$first" = "$second" ]; then echo "    => existing shim reused (same file id and mtime)"; else echo "    => shim not reused"; fi
  echo "  leftover temp/probe files in state: $(cd "$LAB/state" && ls -A | grep -E '^\.(fm-mode-probe|fm-tool)' | tr '\n' ' ')"
  echo
done
