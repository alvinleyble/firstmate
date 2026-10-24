#!/usr/bin/env bash
# drive7.sh <scratch>: the reported bootstrap symptom, local phase only, base vs target.
set -u
SCRATCH=$1
WT=/c/Users/amfne/.no-mistakes/worktrees/efaf735780a2/01M5NK0KCFYG02X2CBAAME90JF
BASE="$SCRATCH/base"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
umask 022
for LABEL in base target; do
  if [ "$LABEL" = base ]; then ROOT=$BASE; else ROOT=$WT; fi
  LAB="$SCRATCH/$LABEL/bootstrap-home"
  "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
  # One durable task that owns a PR, so startup's `arm --if-owned` has work to do.
  printf '%s\n' window=firstmate:fm-task-a endpoint_task_id=task-a "worktree=$LAB/wt" \
    "project=$LAB/project" kind=ship mode=no-mistakes pr=https://github.com/o/r/pull/1 > "$LAB/state/task-a.meta"
  chmod 0600 "$LAB/state/task-a.meta"
  echo "=== [$LABEL] S9 FM_HOME=<lab> FM_BOOTSTRAP_NETWORK=skip bin/fm-bootstrap.sh"
  echo "  owned contributions: $(FM_HOME="$LAB" "$ROOT/bin/fm-contributions.sh" owned 2>&1 | tr -d '\r' | tr '\n' ' ')"
  start=$(date +%s)
  FM_HOME="$LAB" FM_BOOTSTRAP_NETWORK=skip timeout 400 "$ROOT/bin/fm-bootstrap.sh" > "$SCRATCH/$LABEL/bootstrap.out" 2>&1
  rc=$?
  echo "  bootstrap exit=$rc after $(( $(date +%s) - start ))s; full output: $LABEL-bootstrap-output.txt"
  echo "  lines about custom checks / contribution observation:"
  grep -nE 'custom check|contribution|contributions' "$SCRATCH/$LABEL/bootstrap.out" | sed 's/^/    /' || echo "    (none)"
  echo "  contributions artifacts in state: $(cd "$LAB/state" && ls -A | grep '^contributions\.' | tr '\n' ' ')"
  cp "$SCRATCH/$LABEL/bootstrap.out" "/c/Users/amfne/.no-mistakes/evidence/01M5NK0KCFYG02X2CBAAME90JF/10-$LABEL-bootstrap-output.txt"
  echo
done
