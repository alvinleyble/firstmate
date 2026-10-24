#!/usr/bin/env bash
# drive6.sh <scratch>: guards that must stay in force on the noacl drive (target only).
set -u
SCRATCH=$1
WT=/c/Users/amfne/.no-mistakes/worktrees/efaf735780a2/01M5NK0KCFYG02X2CBAAME90JF
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
umask 022
run() { local desc=$1 rc; shift; echo "\$ $desc"; "$@" > "$SCRATCH/.out" 2> "$SCRATCH/.err"; rc=$?
  sed 's/^/    stdout: /' "$SCRATCH/.out"; sed 's/^/    stderr: /' "$SCRATCH/.err"; echo "    exit=$rc"; return $rc; }
LAB="$SCRATCH/adversarial-home"
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
S="$LAB/state"
write_check() { printf '#!/usr/bin/env bash\necho custom-check-ran\n' > "$S/custom.check.sh"; chmod 0700 "$S/custom.check.sh"; }
echo "=== [target] S7 guards on the real noacl drive (OSTYPE=$OSTYPE)"
echo "--- baseline: a plain private custom check registers ---"
write_check
run "FM_HOME=<lab> bin/fm-check-register.sh custom" env FM_HOME="$LAB" "$WT/bin/fm-check-register.sh" custom
rm -f "$S/custom.check-trust"
echo "--- single-link test: a hardlinked custom check ---"
ln "$S/custom.check.sh" "$LAB/outside-alias"
echo "    link count: $(stat -c %h "$S/custom.check.sh")"
run "FM_HOME=<lab> bin/fm-check-register.sh custom" env FM_HOME="$LAB" "$WT/bin/fm-check-register.sh" custom
rm -f "$LAB/outside-alias"
echo "--- type test: a directory at the custom check path ---"
rm -f "$S/custom.check.sh"; mkdir "$S/custom.check.sh"
run "FM_HOME=<lab> bin/fm-check-register.sh custom" env FM_HOME="$LAB" "$WT/bin/fm-check-register.sh" custom
rmdir "$S/custom.check.sh"
echo "--- symlink test: a native symlink at the custom check path ---"
printf '#!/usr/bin/env bash\necho outside\n' > "$LAB/outside-check.sh"
MSYS=winsymlinks:nativestrict ln -s "$LAB/outside-check.sh" "$S/custom.check.sh" 2>&1 | sed 's/^/    ln: /'
if [ -L "$S/custom.check.sh" ]; then
  echo "    native symlink created: $(readlink "$S/custom.check.sh")"
  run "FM_HOME=<lab> bin/fm-check-register.sh custom" env FM_HOME="$LAB" "$WT/bin/fm-check-register.sh" custom
else
  echo "    native symlink could not be created on this host"
fi
rm -f "$S/custom.check.sh" "$LAB/outside-check.sh"
echo "--- OS gate: same entrypoint, same noacl file, OSTYPE forced to linux-gnu (exact comparison) ---"
write_check
echo "    custom.check.sh read mode: $(stat -c %a "$S/custom.check.sh")"
run "OSTYPE=linux-gnu; . bin/fm-check-register.sh custom" \
  env FM_HOME="$LAB" bash -c 'OSTYPE=linux-gnu; . "$1" custom' _ "$WT/bin/fm-check-register.sh"
run "OSTYPE=msys;      . bin/fm-check-register.sh custom" \
  env FM_HOME="$LAB" bash -c 'OSTYPE=msys; . "$1" custom' _ "$WT/bin/fm-check-register.sh"
echo "--- tampered bytes after registration are still refused (trust binding untouched) ---"
printf 'echo tampered\n' >> "$S/custom.check.sh"
run "fm_custom_check_registered <state> custom (after tamper)" \
  bash -c '. "$1/bin/fm-pr-lib.sh"; . "$1/bin/fm-check-lib.sh"; fm_custom_check_registered "$2" custom && echo registered || { echo "not registered"; exit 1; }' _ "$WT" "$S"
echo "--- procevent owner token still compared ---"
H64=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
TOKEN=sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
(umask 077; mkdir "$S/procevent")
printf '%s\n' adapter=demo owner=extension extension_schema=fm-procevent-extension-owner.v1 \
  extension_id=demo.ext extension_version=1.0.0 capability_version=1 \
  "package_digest=sha256:$H64" "binding_digest=sha256:$H64" config_ref=demo-config \
  "registration_token=$TOKEN" argc=0 argv: > "$S/procevent/src-a.source"
chmod 0600 "$S/procevent/src-a.source"
run "bin/fm-procevent.sh retire src-a --if-owner <wrong token>" env FM_HOME="$LAB" "$WT/bin/fm-procevent.sh" retire src-a --if-owner "sha256:$H64"
run "bin/fm-procevent.sh retire src-a --if-owner <right token>" env FM_HOME="$LAB" "$WT/bin/fm-procevent.sh" retire src-a --if-owner "$TOKEN"
echo "    src-a.source after: $([ -e "$S/procevent/src-a.source" ] && echo present || echo retired)"
echo "--- probe is cached per directory per process and removed ---"
mkdir -p "$SCRATCH/mktemp-log-bin" "$LAB/other"
REAL_MKTEMP=$(command -v mktemp)
printf '#!/usr/bin/env bash\ncase "$*" in *.fm-mode-probe.*) printf "%%s\n" "$*" >> %q ;; esac\nexec %q "$@"\n' "$SCRATCH/mktemp.log" "$REAL_MKTEMP" > "$SCRATCH/mktemp-log-bin/mktemp"
chmod +x "$SCRATCH/mktemp-log-bin/mktemp"; : > "$SCRATCH/mktemp.log"
for f in a b c d e; do printf 'x\n' > "$S/f-$f"; chmod 0600 "$S/f-$f"; done
printf 'x\n' > "$LAB/other/g"; chmod 0600 "$LAB/other/g"
PATH="$SCRATCH/mktemp-log-bin:$PATH" bash -c '
  . "$1/bin/fm-pr-lib.sh"
  for f in a b c d e; do fm_pr_file_mode_is "$2/f-$f" 600 && echo "  f-$f accepted as 600 (reads $(fm_pr_file_mode "$2/f-$f"))"; done
  fm_pr_file_mode_is "$3/g" 600 && echo "  other/g accepted as 600 (reads $(fm_pr_file_mode "$3/g"))"
' _ "$WT" "$S" "$LAB/other"
echo "    probes created in that one process: $(wc -l < "$SCRATCH/mktemp.log") (one per directory)"
sed 's/^/      mktemp /' "$SCRATCH/mktemp.log"
echo "    probe files left anywhere in the lab: $(find "$LAB" -name '.fm-mode-probe.*' | wc -l)"
