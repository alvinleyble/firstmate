#!/usr/bin/env bash
# drive4.sh <scratch>: arm each check shim twice (base vs target) and show reuse.
set -u
SCRATCH=$1
WT=/c/Users/amfne/.no-mistakes/worktrees/efaf735780a2/01M5NK0KCFYG02X2CBAAME90JF
BASE="$SCRATCH/base"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
umask 022
run() { local desc=$1 rc; shift; echo "\$ $desc"; "$@" > "$SCRATCH/.out" 2> "$SCRATCH/.err"; rc=$?
  sed 's/^/    stdout: /' "$SCRATCH/.out"; sed 's/^/    stderr: /' "$SCRATCH/.err"; echo "    exit=$rc"; return $rc; }
ident() { [ -f "$1" ] && printf 'fileid=%s mtime_ns=%s mode(read)=%s' "$(stat -c %i "$1")" "$(stat -c %.9Y "$1" 2>/dev/null || stat -c %Y "$1")" "$(stat -c %a "$1")" || printf 'absent'; }
for LABEL in base target; do
  if [ "$LABEL" = base ]; then ROOT=$BASE; else ROOT=$WT; fi
  LAB="$SCRATCH/$LABEL/shim-home"
  "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
  echo "=== [$LABEL] S5 check-shim arm and re-arm"
  for pair in fm-mail-check.sh:mail fm-startup-growth-check.sh:startup-growth fm-tool-update-check.sh:tool-update; do
    script=${pair%%:*}; id=${pair#*:}
    shim="$LAB/state/$id.check.sh"
    run "FM_HOME=<lab> bin/$script arm   (first)" env FM_HOME="$LAB" "$ROOT/bin/$script" arm
    first=$(ident "$shim"); echo "    shim after first arm:  $first"
    sleep 1.1
    run "FM_HOME=<lab> bin/$script arm   (again)" env FM_HOME="$LAB" "$ROOT/bin/$script" arm
    second=$(ident "$shim"); echo "    shim after second arm: $second"
    if [ "$first" != absent ] && [ "$first" = "$second" ]; then echo "    => existing shim reused (same file id and mtime)"; else echo "    => shim not reused"; fi
  done
  echo "  leftover temp/probe files in state: $(cd "$LAB/state" && ls -A | grep -E '^\.(fm-mode-probe|fm-mail-check|fm-startup|fm-tool|fm-custom)' | tr '\n' ' ')"
  echo
done
