#!/usr/bin/env bash
# fm-ps-lib.sh - procps-style `ps` field selection on Git Bash/MSYS and Cygwin.
#
# Firstmate reads processes through `ps -o <field>= -p <pid>` and the
# all-process forms `ps -A -o ...`, `ps -eo ...`, and `ps -axo ...`. Git Bash's
# ps is Cygwin's own, which
# rejects -o field selection outright, so on that platform every such read
# fails and every caller that keys a decision on it (the session lock's harness
# ancestry, watcher identity, teardown process groups) fails closed. Sourcing
# this file on MSYS or Cygwin defines a `ps` shell function that answers the
# procps forms firstmate uses from /proc, the same files fm_pid_identity in
# fm-wake-lib.sh already reads there, and hands every other form to the native
# ps unchanged. It stands aside whenever a ps other than the platform's own
# (/usr/bin/ps or /bin/ps) comes first on PATH, such as a test's fake. On every
# other platform sourcing it defines no `ps` function.
#
# Supported: -o <fields> (repeatable, comma lists, every field suffixed "=" so
# no header is printed), -p <pid[,pid...]>, -u <numeric uid>, and -A, -e, -eo,
# -axo for all processes. Fields: pid, ppid, pgid, comm, args/command, lstart,
# stat/state. Any other option or field, including -t, goes to the native ps.
# Values are printed space-separated, one process per line; like procps the
# status is 1 when no selected process exists.
#
# The Windows boundary: a process started by a native Windows program (Claude
# Code's tool and hook shells, a Herdr pane shell) has MSYS parent pid 1, so a
# parent walk stops before it reaches the harness that started it. For such a
# process ppid resolves through the Windows parent chain to the nearest
# ancestor that has an MSYS pid, passing only through Windows-only shell
# launchers (bash.exe, sh.exe, cmd.exe, conhost.exe). The chain comes from one
# PowerShell read of the whole Windows process table per ps call, shared by
# every process that call lists, and each answer is cached per process start.
# Any other Windows-only ancestor, a parent created after its child (a recycled
# Windows pid), or an unreadable table leaves ppid at 1, so a walk can stop
# short but never cross into an unrelated process.
#
# fm_ps_pid_from_winpid <winpid> prints the MSYS pid of a Windows pid (Claude
# Code's CLAUDE_PID is one), or returns 1 when that process has none.
#
# Test seams: FM_PROC_ROOT_OVERRIDE replaces /proc, FM_PS_FORCE_PROC=1 enables
# the shim on any platform, FM_PS_WINDOWS_TABLE_CMD replaces the PowerShell
# reader (it prints one "winpid<TAB>parent<TAB>name<TAB>creation-epoch-ms" line
# per Windows process), and FM_PS_CACHE_DIR replaces the per-user
# resolved-parent cache directory.
# This file is sourced by scripts and has no side effects on source beyond
# defining functions.

fm_ps_proc_platform() {
  [ "${FM_PS_FORCE_PROC:-0}" = 1 ] && return 0
  case "${OSTYPE:-}" in
    msys* | cygwin*) return 0 ;;
  esac
  return 1
}

# True when `ps` answers from /proc here: on the platform, and only in place of
# the platform's own ps. Any other ps first on PATH (a test fake, an installed
# procps) keeps answering for itself, and its pids are not MSYS pids.
fm_ps_proc_active() {
  [ "${FM_PS_FORCE_PROC:-0}" = 1 ] && return 0
  fm_ps_proc_platform || return 1
  if [ "${_FM_PS_PATH_SEEN-}" != "$PATH" ]; then
    _FM_PS_NATIVE_PATH=$(type -P ps 2>/dev/null)
    _FM_PS_PATH_SEEN=$PATH
  fi
  case "$_FM_PS_NATIVE_PATH" in
    /usr/bin/ps | /bin/ps) return 0 ;;
  esac
  return 1
}

_fm_ps_root() {
  _FM_PS_ROOT=${FM_PROC_ROOT_OVERRIDE:-/proc}
}

# Read the first line of file $2 into variable $1 without forking.
_fm_ps_read() {  # <var> <file>
  local _fm_ps_line=''
  [ -r "$2" ] || return 1
  IFS= read -r _fm_ps_line < "$2" || [ -n "$_fm_ps_line" ] || return 1
  printf -v "$1" '%s' "$_fm_ps_line"
}

# Split /proc/<pid>/stat after the final ")" into _FM_PS_STAT, so index 0 is
# the state and index 19 the start time in clock ticks.
_FM_PS_STAT=()
_fm_ps_stat() {  # <pid>
  local line
  _fm_ps_root
  _fm_ps_read line "$_FM_PS_ROOT/$1/stat" || return 1
  read -r -a _FM_PS_STAT <<< "${line##*)}"
  [ "${#_FM_PS_STAT[@]}" -ge 20 ]
}

_FM_PS_TICKS=
_FM_PS_BTIME=
_fm_ps_clock() {
  local key value
  if [ -z "$_FM_PS_TICKS" ]; then
    _FM_PS_TICKS=${FM_PS_CLK_TCK:-$(getconf CLK_TCK 2>/dev/null)}
    case "$_FM_PS_TICKS" in '' | *[!0-9]* | 0) _FM_PS_TICKS=100 ;; esac
  fi
  [ -n "$_FM_PS_BTIME" ] && return 0
  _fm_ps_root
  [ -r "$_FM_PS_ROOT/stat" ] || return 1
  while read -r key value _; do
    if [ "$key" = btime ]; then
      _FM_PS_BTIME=$value
      return 0
    fi
  done < "$_FM_PS_ROOT/stat"
  return 1
}

# Each _fm_ps_value_* sets _FM_PS_VALUE for process $1 or returns 1.
_FM_PS_VALUE=

_fm_ps_value_lstart() {  # <pid>
  local epoch
  _fm_ps_stat "$1" && _fm_ps_clock || return 1
  epoch=$((_FM_PS_BTIME + _FM_PS_STAT[19] / _FM_PS_TICKS))
  # printf's own clock format needs bash 4.2; Git Bash has it, and the date
  # fallback keeps the forced test mode working under an older bash.
  printf -v _FM_PS_VALUE '%(%a %b %e %H:%M:%S %Y)T' "$epoch" 2>/dev/null && return 0
  _FM_PS_VALUE=$(LC_ALL=C date -d "@$epoch" '+%a %b %e %H:%M:%S %Y' 2>/dev/null ||
    LC_ALL=C date -r "$epoch" '+%a %b %e %H:%M:%S %Y' 2>/dev/null)
}

_fm_ps_value_comm() {  # <pid>
  local exe
  _fm_ps_root
  _fm_ps_read exe "$_FM_PS_ROOT/$1/exename" || return 1
  exe=${exe##*/}
  exe=${exe##*\\}
  _FM_PS_VALUE=${exe%.exe}
}

_fm_ps_value_args() {  # <pid>
  local part args=''
  _fm_ps_root
  [ -r "$_FM_PS_ROOT/$1/cmdline" ] || return 1
  while IFS= read -r -d '' part || [ -n "$part" ]; do
    args=${args:+$args }$part
  done < "$_FM_PS_ROOT/$1/cmdline"
  if [ -z "$args" ]; then
    _fm_ps_value_comm "$1"
    return
  fi
  _FM_PS_VALUE=$args
}

# Set _FM_PS_VALUE to the MSYS pid of Windows pid $1, or return 1.
_fm_ps_from_winpid() {  # <winpid>
  local dir pid winpid
  case "$1" in '' | *[!0-9]*) return 1 ;; esac
  _fm_ps_root
  for dir in "$_FM_PS_ROOT"/[0-9]*; do
    pid=${dir##*/}
    case "$pid" in *[!0-9]*) continue ;; esac
    _fm_ps_read winpid "$dir/winpid" || continue
    if [ "$winpid" = "$1" ]; then
      _FM_PS_VALUE=$pid
      return 0
    fi
  done
  return 1
}

fm_ps_pid_from_winpid() {  # <winpid>
  _fm_ps_from_winpid "$1" || return 1
  printf '%s\n' "$_FM_PS_VALUE"
}

# Print "winpid<TAB>parent<TAB>name<TAB>creation-epoch-ms" for every Windows
# process.
_fm_ps_windows_table() {
  local script encoded
  if [ -n "${FM_PS_WINDOWS_TABLE_CMD:-}" ]; then
    "$FM_PS_WINDOWS_TABLE_CMD"
    return
  fi
  command -v powershell.exe >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2016 # PowerShell source: its $ variables are PowerShell's own.
  script='Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name,CreationDate -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.CreationDate) {
    "{0}`t{1}`t{2}`t{3}" -f $_.ProcessId, $_.ParentProcessId, $_.Name, ([DateTimeOffset]$_.CreationDate).ToUnixTimeMilliseconds()
  }
}'
  encoded=$(printf '%s' "$script" | iconv -f UTF-8 -t UTF-16LE 2>/dev/null | base64 -w 0 2>/dev/null) || return 1
  [ -n "$encoded" ] || return 1
  MSYS2_ARG_CONV_EXCL='*' timeout 20 powershell.exe -NoProfile -NonInteractive \
    -EncodedCommand "$encoded" 2>/dev/null | tr -d '\r'
}

# The Windows process table indexed by Windows pid, with the MSYS pid of each
# Windows pid that has one, read at most once per ps call: _FM_PS_TABLE is
# empty until the read and then "ok" or "none".
_FM_PS_TABLE=
_FM_PS_WIN_PARENT=()
_FM_PS_WIN_NAME=()
_FM_PS_WIN_CREATED=()
_FM_PS_WIN_MSYS=()

_fm_ps_windows_table_load() {
  local table win parent name created dir pid winpid
  case "$_FM_PS_TABLE" in
    ok) return 0 ;;
    none) return 1 ;;
  esac
  _FM_PS_TABLE=none
  _FM_PS_WIN_PARENT=()
  _FM_PS_WIN_NAME=()
  _FM_PS_WIN_CREATED=()
  _FM_PS_WIN_MSYS=()
  table=$(_fm_ps_windows_table) || table=
  while IFS=$'\t' read -r win parent name created; do
    case "$win" in '' | *[!0-9]*) continue ;; esac
    case "$parent" in '' | *[!0-9]*) continue ;; esac
    case "$created" in '' | *[!0-9]*) continue ;; esac
    _FM_PS_WIN_PARENT[win]=$parent
    _FM_PS_WIN_NAME[win]=$name
    _FM_PS_WIN_CREATED[win]=$created
  done <<EOF
$table
EOF
  [ "${#_FM_PS_WIN_CREATED[@]}" -gt 0 ] || return 1
  _fm_ps_root
  for dir in "$_FM_PS_ROOT"/[0-9]*; do
    pid=${dir##*/}
    case "$pid" in *[!0-9]*) continue ;; esac
    _fm_ps_read winpid "$dir/winpid" || continue
    case "$winpid" in '' | *[!0-9]*) continue ;; esac
    _FM_PS_WIN_MSYS[winpid]=$pid
  done
  _FM_PS_TABLE=ok
}

# Set _FM_PS_VALUE to the MSYS pid of the nearest of the first seven Windows
# ancestors of MSYS process $1 that has one, crossing only Windows-only shell
# launchers, or return 1 when there is none. The answer is cached per process
# start, because a process's parent never changes.
_fm_ps_windows_parent() {  # <pid>
  local pid=$1 winpid start cache_dir cache_file cached child cur hop=0 mapped=none
  _fm_ps_root
  _fm_ps_read winpid "$_FM_PS_ROOT/$pid/winpid" || return 1
  case "$winpid" in '' | *[!0-9]*) return 1 ;; esac
  _fm_ps_stat "$pid" || return 1
  start=${_FM_PS_STAT[19]}
  cache_dir=${FM_PS_CACHE_DIR:-${TMPDIR:-/tmp}/fm-ps-windows-parent}
  cache_file="$cache_dir/$pid-$winpid-$start"
  if _fm_ps_read cached "$cache_file"; then
    case "$cached" in
      none) return 1 ;;
      '' | *[!0-9]*) ;;
      *) _FM_PS_VALUE=$cached; return 0 ;;
    esac
  fi
  _fm_ps_windows_table_load || return 1
  [ -n "${_FM_PS_WIN_CREATED[winpid]:-}" ] || return 1
  child=$winpid
  while [ "$hop" -lt 7 ]; do
    cur=${_FM_PS_WIN_PARENT[child]}
    [ -n "${_FM_PS_WIN_CREATED[cur]:-}" ] || break
    # A recycled Windows pid would name a process created after its child.
    [ "${_FM_PS_WIN_CREATED[cur]}" -le "${_FM_PS_WIN_CREATED[child]}" ] || break
    if [ -n "${_FM_PS_WIN_MSYS[cur]:-}" ]; then
      mapped=${_FM_PS_WIN_MSYS[cur]}
      break
    fi
    case "${_FM_PS_WIN_NAME[cur]}" in
      [Bb][Aa][Ss][Hh].[Ee][Xx][Ee] | [Ss][Hh].[Ee][Xx][Ee] | \
        [Cc][Mm][Dd].[Ee][Xx][Ee] | [Cc][Oo][Nn][Hh][Oo][Ss][Tt].[Ee][Xx][Ee]) ;;
      *) break ;;
    esac
    child=$cur
    hop=$((hop + 1))
  done
  if mkdir -p "$cache_dir" 2>/dev/null; then
    { printf '%s\n' "$mapped" > "$cache_file.$$" && mv -f "$cache_file.$$" "$cache_file"; } 2>/dev/null || true
  fi
  [ "$mapped" != none ] || return 1
  _FM_PS_VALUE=$mapped
}

_fm_ps_value_ppid() {  # <pid>
  local ppid
  _fm_ps_root
  _fm_ps_read ppid "$_FM_PS_ROOT/$1/ppid" || return 1
  # MSYS has no pid 1 of its own: parent 1 means a native Windows parent.
  if [ "$ppid" = 1 ] && [ ! -e "$_FM_PS_ROOT/1" ] && _fm_ps_windows_parent "$1"; then
    return 0
  fi
  _FM_PS_VALUE=$ppid
}

# Set _FM_PS_VALUE to field $2 of process $1; an unreadable field is an empty
# value.
_fm_ps_value() {  # <pid> <field>
  local pid=$1
  _FM_PS_VALUE=
  _fm_ps_root
  case "$2" in
    pid) _FM_PS_VALUE=$pid ;;
    ppid) _fm_ps_value_ppid "$pid" || _FM_PS_VALUE= ;;
    pgid) _fm_ps_read _FM_PS_VALUE "$_FM_PS_ROOT/$pid/pgid" || _FM_PS_VALUE= ;;
    comm) _fm_ps_value_comm "$pid" || _FM_PS_VALUE= ;;
    args | command) _fm_ps_value_args "$pid" || _FM_PS_VALUE= ;;
    lstart) _fm_ps_value_lstart "$pid" || _FM_PS_VALUE= ;;
    stat | state) _fm_ps_stat "$pid" && _FM_PS_VALUE=${_FM_PS_STAT[0]} ;;
  esac
  return 0
}

fm_ps_proc() {
  local -a original=("$@") specs=() fields=() pids=() names=() more=()
  local all=0 arg spec name pid line dir printed=0 uid_filter='' uid
  fm_ps_proc_active || { command ps "$@"; return; }
  _FM_PS_TABLE=
  while [ "$#" -gt 0 ]; do
    arg=$1
    case "$arg" in
      -u)
        case "${2:-}" in '' | *[!0-9]*) command ps "${original[@]}"; return ;; esac
        uid_filter=$2
        all=1
        shift 2
        ;;
      -o | -eo | -axo)
        [ "$#" -ge 2 ] || { command ps "${original[@]}"; return; }
        [ "$arg" = -o ] || all=1
        specs+=("$2")
        shift 2
        ;;
      -p)
        [ "$#" -ge 2 ] || { command ps "${original[@]}"; return; }
        IFS=', ' read -r -a more <<< "$2"
        pids+=("${more[@]}")
        shift 2
        ;;
      -A | -e) all=1; shift ;;
      *) command ps "${original[@]}"; return ;;
    esac
  done
  [ "${#specs[@]}" -gt 0 ] || { command ps "${original[@]}"; return; }
  for spec in "${specs[@]}"; do
    IFS=, read -r -a names <<< "$spec"
    for name in "${names[@]}"; do
      case "$name" in
        pid= | ppid= | pgid= | comm= | args= | command= | lstart= | stat= | state=) fields+=("${name%=}") ;;
        *) command ps "${original[@]}"; return ;;
      esac
    done
  done
  _fm_ps_root
  if [ "$all" -eq 1 ]; then
    pids=()
    for dir in "$_FM_PS_ROOT"/[0-9]*; do
      pid=${dir##*/}
      case "$pid" in *[!0-9]*) continue ;; esac
      pids+=("$pid")
    done
  fi
  [ "${#pids[@]}" -gt 0 ] || { command ps "${original[@]}"; return; }
  for pid in "${pids[@]}"; do
    case "$pid" in '' | *[!0-9]*) continue ;; esac
    [ -d "$_FM_PS_ROOT/$pid" ] || continue
    if [ -n "$uid_filter" ]; then
      _fm_ps_read uid "$_FM_PS_ROOT/$pid/uid" || continue
      [ "${uid%%[!0-9]*}" = "$uid_filter" ] || continue
    fi
    line=
    for name in "${fields[@]}"; do
      _fm_ps_value "$pid" "$name"
      line=${line:+$line }$_FM_PS_VALUE
    done
    printf '%s\n' "$line"
    printed=1
  done
  [ "$printed" -eq 1 ]
}

if fm_ps_proc_platform; then
  # Resolved once here so every later call, including those in command
  # substitutions, inherits it without forking; a changed PATH re-resolves.
  _FM_PS_NATIVE_PATH=$(type -P ps 2>/dev/null)
  _FM_PS_PATH_SEEN=$PATH
  ps() { fm_ps_proc "$@"; }
fi
