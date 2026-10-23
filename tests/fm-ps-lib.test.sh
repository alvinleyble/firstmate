#!/usr/bin/env bash
# Behavior tests for bin/fm-ps-lib.sh, the procps-style `ps` that firstmate
# supplies on Git Bash/MSYS, where the native ps rejects -o field selection.
#
# Every case runs the shim against a fabricated /proc (FM_PROC_ROOT_OVERRIDE)
# with FM_PS_FORCE_PROC=1, so the suite proves the same reads on every host.
# The Windows-boundary cases replace the PowerShell process-table reader with a
# stub (FM_PS_WINDOWS_TABLE_CMD) that also counts how often it is asked, and
# the last case runs the real session-lock identity through the shim, which is
# the read that made every Windows session read-only before it existed.
# shellcheck disable=SC2016 # single quotes are deliberate: $0 and $$ expand inside the child shell
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-ps-lib)
LIB="$ROOT/bin/fm-ps-lib.sh"
SESSION_LIB="$ROOT/bin/fm-session-lock-lib.sh"

BTIME=1792000000
TICKS=1000

# proc_entry <root> <pid> <ppid> <exename> <winpid> <start-ticks> [<arg>...]
proc_entry() {
  local root=$1 pid=$2 ppid=$3 exe=$4 winpid=$5 start=$6 comm
  shift 6
  mkdir -p "$root/$pid"
  printf '%s\n' "$ppid" > "$root/$pid/ppid"
  printf '%s\n' "$pid" > "$root/$pid/pgid"
  printf '%s\n' "$exe" > "$root/$pid/exename"
  printf '%s\n' "$winpid" > "$root/$pid/winpid"
  printf '197609\n' > "$root/$pid/uid"
  printf '/dev/cons0\n' > "$root/$pid/ctty"
  comm=${exe##*/}
  printf '%s (%s) S %s %s %s 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0 0\n' \
    "$pid" "$comm" "$ppid" "$pid" "$pid" "$start" > "$root/$pid/stat"
  if [ "$#" -gt 0 ]; then
    printf '%s\0' "$@" > "$root/$pid/cmdline"
  else
    : > "$root/$pid/cmdline"
  fi
}

new_proc() {  # <name> -> echoes a proc root with a btime line
  local root="$TMP_ROOT/$1/proc"
  mkdir -p "$root"
  printf 'cpu 0 0 0 0\nbtime %s\n' "$BTIME" > "$root/stat"
  printf '%s\n' "$root"
}

# write_table <file> <line>...: the stub the shim calls for the Windows
# process table.
write_table() {
  local stub=$1 calls=$1.calls
  shift
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf x >> %q\n' "$calls"
    printf 'cat <<'"'"'TABLE'"'"'\n'
    printf '%s\n' "$@"
    printf 'TABLE\n'
  } > "$stub"
  chmod +x "$stub"
}

shim() {  # <proc-root> <expression...>
  local root=$1
  shift
  env FM_PS_FORCE_PROC=1 FM_PROC_ROOT_OVERRIDE="$root" FM_PS_CLK_TCK=$TICKS \
    FM_PS_CACHE_DIR="$root.cache" bash -c ". \"\$0\"; $*" "$LIB"
}

test_fields_are_read_from_proc() {
  local root out rc
  root=$(new_proc fields)
  proc_entry "$root" 42 7 /usr/bin/bash 900 5000 bash -c 'echo hi'
  proc_entry "$root" 7 3 '/c/Users/x/.local/bin/claude.exe' 901 1000 claude --resume
  out=$(shim "$root" 'ps -o pid=,ppid=,pgid=,comm=,stat= -p 42')
  assert_equals "42 7 42 bash S" "$out" "one line carries every requested field in order"
  out=$(shim "$root" 'ps -o comm= -p 7')
  assert_equals "claude" "$out" "comm is the executable basename without .exe"
  out=$(shim "$root" 'ps -o args= -p 42')
  assert_equals "bash -c echo hi" "$out" "args joins the NUL-separated command line"
  # Process 7 started 1000 ticks (one second at 1000 Hz) after boot.
  out=$(TZ=UTC shim "$root" 'ps -p 7 -o lstart=')
  assert_equals "$(TZ=UTC LC_ALL=C date -d "@$((BTIME + 1))" '+%a %b %e %H:%M:%S %Y' 2>/dev/null ||
    TZ=UTC LC_ALL=C date -r $((BTIME + 1)) '+%a %b %e %H:%M:%S %Y')" \
    "$out" "lstart is boot time plus the start ticks"
  out=$(shim "$root" 'ps -o pid= -o ppid= -p 7,42')
  assert_equals $'7 3\n42 7' "$out" "repeated -o and a comma pid list"
  out=$(shim "$root" 'ps -A -o pid=' | sort -n | tr '\n' ' ')
  assert_equals "7 42 " "$out" "-A lists every process"
  out=$(shim "$root" 'ps -axo pid=,state=' | sort -n | tr '\n' ' ')
  assert_equals "7 S 42 S " "$out" "-axo lists every process"
  out=$(shim "$root" 'ps -u 197609 -o pid=' | sort -n | tr '\n' ' ')
  assert_equals "7 42 " "$out" "-u keeps that account's processes"
  out=$(shim "$root" 'ps -u 1 -o pid=') && rc=0 || rc=$?
  expect_code 1 "$rc" "-u with no matching process"
  shim "$root" 'ps -o comm= -p 999' >/dev/null && rc=0 || rc=$?
  expect_code 1 "$rc" "a missing pid exits 1 like procps"
  pass "fm-ps-lib answers procps field reads from /proc"
}

test_other_forms_go_to_the_native_ps() {
  local root fakebin form out
  root=$(new_proc native)
  proc_entry "$root" 42 7 /usr/bin/bash 900 5000 bash
  fakebin=$(fm_fakebin "$TMP_ROOT/native/bin")
  printf '#!/bin/sh\necho "native $*"\n' > "$fakebin/ps"
  chmod +x "$fakebin/ps"
  # -Eww appends the environment and %cpu is a measurement; /proc answers
  # neither, so both, like every form outside the supported set, stay native.
  for form in '-Eww -o command= -p 42' '-A -o %cpu=' '-o tpgid= -p 42' \
    '-o pid=PID -p 42' '-ax -o pid=' '-p42 -o pid=' '-t cons0 -o pid='; do
    out=$(PATH="$fakebin:$PATH" shim "$root" "ps $form")
    assert_equals "native $form" "$out" "ps $form is answered by the native ps"
  done
  pass "fm-ps-lib hands every unsupported option and field to the native ps"
}

test_windows_parent_resolves_through_shell_launchers() {
  local root stub out calls
  root=$(new_proc boundary)
  # Claude's tool shell: an MSYS bash whose parent is the native Git launcher.
  proc_entry "$root" 50 1 /usr/bin/bash 500 9000 bash -c 'fm-lock'
  proc_entry "$root" 77 70 /c/Users/x/.local/bin/claude 300 4000 claude
  stub="$TMP_ROOT/boundary/table"
  write_table "$stub" \
    $'500\t400\tbash.exe\t3000' \
    $'400\t300\tbash.exe\t2000' \
    $'300\t200\tclaude.exe\t1000'
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'ps -o ppid= -p 50')
  assert_equals "77" "$out" "a parent-1 shell resolves to the Claude process past the launcher"
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'ps -o ppid= -p 50')
  assert_equals "77" "$out" "the cached answer is the same"
  calls=$(cat "$stub.calls")
  assert_equals "x" "$calls" "the Windows table is read once per process start"
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'fm_ps_pid_from_winpid 300')
  assert_equals "77" "$out" "a Windows pid maps to its MSYS pid"
  pass "fm-ps-lib resolves a native parent through Git Bash launchers"
}

test_all_process_scan_reads_the_windows_table_once() {
  local root stub out calls
  root=$(new_proc scan)
  # Three tool and pane shells, each with MSYS parent 1, under two harnesses.
  proc_entry "$root" 50 1 /usr/bin/bash 500 9000 bash
  proc_entry "$root" 51 1 /usr/bin/bash 510 9100 bash
  proc_entry "$root" 52 1 /usr/bin/bash 520 9200 bash
  proc_entry "$root" 77 70 /c/Users/x/.local/bin/claude 300 4000 claude
  proc_entry "$root" 88 80 /c/Users/x/.local/bin/claude 600 4500 claude
  stub="$TMP_ROOT/scan/table"
  write_table "$stub" \
    $'500\t400\tbash.exe\t3000' \
    $'510\t410\tbash.exe\t3100' \
    $'520\t600\tbash.exe\t3200' \
    $'400\t300\tbash.exe\t2000' \
    $'410\t300\tcmd.exe\t2100' \
    $'300\t200\tclaude.exe\t1000' \
    $'600\t250\tclaude.exe\t1500'
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'ps -A -o pid= -o ppid=' | sort -n | tr '\n' ' ')
  assert_equals "50 77 51 77 52 88 77 70 88 80 " "$out" "every parent-1 shell resolves to its own harness"
  calls=$(cat "$stub.calls")
  assert_equals "x" "$calls" "one all-process scan reads the Windows table once"
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'ps -eo pid=,ppid=' | sort -n | tr '\n' ' ')
  assert_equals "50 77 51 77 52 88 77 70 88 80 " "$out" "a later scan answers the same"
  calls=$(cat "$stub.calls")
  assert_equals "x" "$calls" "a later scan answers from the per-process cache"
  pass "fm-ps-lib resolves every parent-1 process of a scan from one Windows table read"
}

test_windows_parent_never_crosses_other_processes() {
  local root stub out
  root=$(new_proc foreign)
  proc_entry "$root" 50 1 /usr/bin/bash 500 9000 bash
  proc_entry "$root" 77 70 /c/Users/x/.local/bin/claude 300 4000 claude
  stub="$TMP_ROOT/foreign/table"
  # A native multiplexer sits between the shell and an unrelated Claude.
  write_table "$stub" \
    $'500\t400\tbash.exe\t3000' \
    $'400\t300\therdr.exe\t2000' \
    $'300\t200\tclaude.exe\t1000'
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'ps -o ppid= -p 50')
  assert_equals "1" "$out" "a Windows-only non-shell ancestor stops the crossing"

  root=$(new_proc recycled)
  proc_entry "$root" 50 1 /usr/bin/bash 500 9000 bash
  proc_entry "$root" 77 70 /c/Users/x/.local/bin/claude 400 4000 claude
  stub="$TMP_ROOT/recycled/table"
  # The recorded parent pid now names a process created after the child.
  write_table "$stub" \
    $'500\t400\tbash.exe\t3000' \
    $'400\t200\tclaude.exe\t8000'
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'ps -o ppid= -p 50')
  assert_equals "1" "$out" "a recycled Windows parent pid is not followed"

  root=$(new_proc unreadable)
  proc_entry "$root" 50 1 /usr/bin/bash 500 9000 bash
  stub="$TMP_ROOT/unreadable/table"
  write_table "$stub"
  out=$(FM_PS_WINDOWS_TABLE_CMD="$stub" shim "$root" 'ps -o ppid= -p 50')
  assert_equals "1" "$out" "an unreadable table leaves the parent at 1"
  pass "fm-ps-lib never crosses into an unrelated Windows process"
}

test_shim_stands_aside_for_another_ps() {
  local root fakebin out
  root=$(new_proc aside)
  proc_entry "$root" 42 7 /usr/bin/bash 900 5000 bash
  fakebin=$(fm_fakebin "$TMP_ROOT/aside/bin")
  printf '#!/bin/sh\necho "fake $*"\n' > "$fakebin/ps"
  chmod +x "$fakebin/ps"
  # Activate on the platform path only, as on a real MSYS host.
  out=$(env OSTYPE=msys PATH="$fakebin:$PATH" FM_PROC_ROOT_OVERRIDE="$root" \
    bash -c 'OSTYPE=msys; . "$0"; ps -o comm= -p 42' "$LIB")
  assert_equals "fake -o comm= -p 42" "$out" "a ps earlier on PATH than the platform's keeps answering"
  pass "fm-ps-lib stands aside for any ps other than the platform's own"
}

test_session_lock_anchors_on_claude_across_the_windows_boundary() {
  local root stub out
  root=$(new_proc session)
  proc_entry "$root" 77 70 /c/Users/x/.local/bin/claude 300 4000 claude
  proc_entry "$root" 70 1 /usr/bin/bash 200 2000 bash -l
  stub="$TMP_ROOT/session/table"
  write_table "$stub" \
    $'500\t400\tbash.exe\t3000' \
    $'400\t300\tbash.exe\t2500' \
    $'300\t200\tclaude.exe\t2000'
  # The expression registers its own shell as the parent-1 tool shell, the
  # shape Claude Code's Bash tool has on Windows, then asks the real library.
  out=$(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_PID \
    FM_PS_FORCE_PROC=1 FM_PROC_ROOT_OVERRIDE="$root" FM_PS_CLK_TCK=$TICKS \
    FM_PS_CACHE_DIR="$root.cache" FM_PS_WINDOWS_TABLE_CMD="$stub" \
    CLAUDE_CODE_SESSION_ID=session-abc CLAUDE_PID=300 \
    bash -c '
      root=$FM_PROC_ROOT_OVERRIDE
      mkdir -p "$root/$$"
      printf "1\n" > "$root/$$/ppid"; printf "%s\n" "$$" > "$root/$$/pgid"
      printf "/usr/bin/bash\n" > "$root/$$/exename"; printf "500\n" > "$root/$$/winpid"
      printf "bash\0-c\0fm-lock\0" > "$root/$$/cmdline"
      printf "%s (bash) S 1 %s %s 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 9000 0 0 0\n" "$$" "$$" "$$" > "$root/$$/stat"
      . "$0"
      kill() { return 0; }
      printf "anchor=%s\n" "$(fm_session_lock_anchor_pid)"
      printf "id=%s\n" "$(fm_session_lock_trusted_session_id)"
    ' "$SESSION_LIB")
  assert_contains "$out" "anchor=77" "the lock anchors on the Claude process by its MSYS pid"
  assert_contains "$out" "id=session-abc" "the Claude session id is trusted across the boundary"
  pass "the session lock finds Claude across the Windows process boundary"
}

test_fields_are_read_from_proc
test_other_forms_go_to_the_native_ps
test_windows_parent_resolves_through_shell_launchers
test_all_process_scan_reads_the_windows_table_once
test_windows_parent_never_crosses_other_processes
test_shim_stands_aside_for_another_ps
test_session_lock_anchors_on_claude_across_the_windows_boundary
