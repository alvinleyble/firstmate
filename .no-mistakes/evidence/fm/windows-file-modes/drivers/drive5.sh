#!/usr/bin/env bash
# drive5.sh <scratch>: procevent extension owner records and exact-700 private directories.
set -u
SCRATCH=$1
WT=/c/Users/amfne/.no-mistakes/worktrees/efaf735780a2/01M5NK0KCFYG02X2CBAAME90JF
BASE="$SCRATCH/base"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
umask 022
run() { local desc=$1 rc; shift; echo "\$ $desc"; "$@" > "$SCRATCH/.out" 2> "$SCRATCH/.err"; rc=$?
  sed 's/^/    stdout: /' "$SCRATCH/.out"; sed 's/^/    stderr: /' "$SCRATCH/.err"; echo "    exit=$rc"; return $rc; }
H64=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
TOKEN=sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
for LABEL in base target; do
  if [ "$LABEL" = base ]; then ROOT=$BASE; else ROOT=$WT; fi
  LAB="$SCRATCH/$LABEL/procevent-home"
  "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
  echo "=== [$LABEL] S6 procevent"
  (umask 077; mkdir "$LAB/state/procevent")
  reg="$LAB/state/procevent/src-a.source"
  printf '%s\n' adapter=demo owner=extension extension_schema=fm-procevent-extension-owner.v1 \
    extension_id=demo.ext extension_version=1.0.0 capability_version=1 \
    "package_digest=sha256:$H64" "binding_digest=sha256:$H64" config_ref=demo-config \
    "registration_token=$TOKEN" argc=0 argv: > "$reg"
  chmod 0600 "$reg"
  echo "  state/procevent/src-a.source written (chmod 0600; read mode $(stat -c %a "$reg"))"
  run "FM_HOME=<lab> bin/fm-procevent.sh retire src-a" env FM_HOME="$LAB" "$ROOT/bin/fm-procevent.sh" retire src-a
  mkdir -p "$LAB/state/results"
  res="$LAB/state/results/src-a.1.result"
  printf 'payload\n' > "$res"; printf 'demo\n' > "${res%.result}.adapter"
  printf '%s\n' schema=fm-procevent-extension-owner.v1 extension_id=demo.ext extension_version=1.0.0 \
    capability_version=1 "package_digest=sha256:$H64" "binding_digest=sha256:$H64" > "${res%.result}.extension"
  chmod 0600 "${res%.result}.extension"
  echo "  results/src-a.1.extension written (chmod 0600; read mode $(stat -c %a "${res%.result}.extension"))"
  run "FM_HOME=<lab> bin/fm-procevent.sh classify <lab>/state/results/src-a.1.result" \
    env FM_HOME="$LAB" "$ROOT/bin/fm-procevent.sh" classify "$res"
  echo "  -- exact-700 private directories (bin/fm-procevent-lib.sh preparers, sourced from $LABEL) --"
  for fn in fm_procevent_capture_inbox_prepare fm_procevent_capture_reservation_prepare fm_procevent_extension_staging_prepare; do
    run "$fn <lab>/state" bash -c '. "$1/bin/fm-pr-lib.sh"; . "$1/bin/fm-procevent-lib.sh"; "$2" "$3"' _ "$ROOT" "$fn" "$LAB/state"
  done
  echo "  state dirs: $(cd "$LAB/state" && for d in procevent procevent-inbox procevent-capture-reservations; do [ -d "$d" ] && printf '%s(read %s) ' "$d" "$(stat -c %a "$d")"; done)"
  echo "  leftover mode probes: $(find "$LAB" -name '.fm-mode-probe.*' | wc -l)"
  echo
done
