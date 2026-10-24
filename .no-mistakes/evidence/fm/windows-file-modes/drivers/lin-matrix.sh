#!/usr/bin/env bash
# lin-matrix.sh <root> <ostype-or-native>: exercise the real private-file checks on a
# filesystem that stores permission bits (container overlayfs).
set -u
ROOT=$1 FORCE=$2
umask 022
W=$(mktemp -d); cd "$W"; mkdir -p state
REAL_MKTEMP=$(command -v mktemp); mkdir -p "$W/.bin"
printf '#!/bin/bash\ncase "$*" in *.fm-mode-probe.*) echo probe >> %q ;; esac\nexec %q "$@"\n' "$W/probe.log" "$REAL_MKTEMP" > "$W/.bin/mktemp"; chmod +x "$W/.bin/mktemp"
: > "$W/probe.log"
PATH="$W/.bin:$PATH" bash -c '
  [ "$2" = native ] || OSTYPE=$2
  . "$1/bin/fm-pr-lib.sh"
  dev=$(fm_pr_file_device state)
  for m in 600 644 640 400 700 755 750; do
    for want in 600 700; do
      f=state/f-$m-$want; printf "x\n" > "$f"; chmod "$m" "$f"
      if fm_pr_private_file_valid "$f" "$want" "$dev"; then r=accept; else r=refuse; fi
      printf "OSTYPE=%-10s chmod=%s required=%s -> %s\n" "$OSTYPE" "$m" "$want" "$r"
    done
  done
  f=state/hl; printf "x\n" > "$f"; chmod 600 "$f"; ln "$f" state/hl2
  if fm_pr_private_file_valid "$f" 600 "$dev"; then r=accept; else r=refuse; fi
  printf "OSTYPE=%-10s chmod=600 hardlinked     -> %s\n" "$OSTYPE" "$r"
' _ "$ROOT" "$FORCE"
echo "probes run: $(wc -l < "$W/probe.log"); probe files left: $(find "$W" -name '.fm-mode-probe.*' | wc -l)"
# The real register entrypoint, same bits-keeping filesystem
H=$(mktemp -d); mkdir -p "$H/state"
printf '#!/usr/bin/env bash\necho hi\n' > "$H/state/c.check.sh"
for m in 755 700; do
  chmod "$m" "$H/state/c.check.sh"; rm -f "$H/state/c.check-trust"
  if [ "$FORCE" = native ]; then
    out=$(FM_HOME=$H "$ROOT/bin/fm-check-register.sh" c 2>&1)
  else
    out=$(FM_HOME=$H bash -c 'OSTYPE=$2; . "$1" c' _ "$ROOT/bin/fm-check-register.sh" "$FORCE" 2>&1)
  fi
  echo "fm-check-register.sh with chmod $m check: $out"
done
