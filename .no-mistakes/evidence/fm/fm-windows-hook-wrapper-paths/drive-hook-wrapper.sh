#!/usr/bin/env bash
# Live driver for firstmate's per-task git hook wrapper (bin/fm-git-strip-ai-trailers.sh).
# Usage: drive-hook-wrapper.sh <firstmate-bin-dir> <label> <scenario...>
# Each scenario builds a throwaway repo under a fresh mktemp dir, installs the wrappers
# the way bin/fm-spawn.sh does (install <state>/<id>.git-hooks <worktree>), then runs the
# worker's git command behind the exact pane launch prefix fm-spawn.sh composes:
#   fm-git-strip-ai-trailers.sh env-file <hooks> <envfile> && . <envfile> || exit 1; <worker cmd>
# Every worker command is bounded by `timeout`, so a self-exec loop shows up as exit 124.
set -u
BIN=$1 LABEL=$2
shift 2
STRIP="$BIN/fm-git-strip-ai-trailers.sh"
LIMIT=${LIMIT:-25}
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_PARAMETERS
export GIT_AUTHOR_NAME='Lab Worker' GIT_AUTHOR_EMAIL='worker@example.invalid'
export GIT_COMMITTER_NAME='Lab Worker' GIT_COMMITTER_EMAIL='worker@example.invalid'
OS=$(uname -s)
fails=0

say() { printf '[%s] %s\n' "$LABEL" "$*"; }
ok() { say "PASS: $*"; }
bad() { say "FAIL: $*"; fails=$((fails + 1)); }

marker_hook() {  # <path> <tag> <logfile>
  mkdir -p "${1%/*}"
  cat >"$1" <<SH
#!/usr/bin/env bash
printf '%s pid=%s GIT_CONFIG_COUNT=%s KEY_0=%s VALUE_0=%s inherited=%s\n' '$2' "\$\$" "\${GIT_CONFIG_COUNT-}" "\${GIT_CONFIG_KEY_0-}" "\${GIT_CONFIG_VALUE_0-}" "\$(git config --get fmtest.inherited 2>/dev/null)" >>'$3'
exit 0
SH
  chmod 755 "$1"
}

setup() {  # sets WORK REPO HOOKS ENVF LOG
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-hookwrap.XXXXXX")
  WORK=$(cd "$WORK" && pwd -P)
  REPO="$WORK/worktrees/task-1"
  HOOKS="$WORK/state/task-1.git-hooks"
  ENVF="$WORK/launch/git-config.1.sh"
  LOG="$WORK/hooks.log"
  mkdir -p "$WORK/state" "$WORK/launch"
  git init -q -b main "$REPO"
  printf 'hello\n' >"$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -q -m init
  git init -q --bare "$WORK/origin.git"
  git -C "$REPO" remote add origin "$WORK/origin.git"
  : >"$LOG"
}

install_wrappers() {
  "$STRIP" install "$HOOKS" "$REPO" || { bad "install failed"; return 1; }
  say "installed wrappers at $HOOKS"
}

# Run <worker cmd> in a fresh bash behind the fm-spawn launch prefix, bounded by LIMIT.
pane() {
  local cmd=$1 q_strip q_hooks q_env
  printf -v q_strip %q "$STRIP"
  printf -v q_hooks %q "$HOOKS"
  printf -v q_env %q "$ENVF"
  local t0=$SECONDS
  OUT=$(cd "$REPO" && timeout "$LIMIT" bash -c "$q_strip env-file $q_hooks $q_env && . $q_env || exit 1; $cmd" 2>&1)
  RC=$?
  ELAPSED=$((SECONDS - t0))
  say "pane cmd: $cmd"
  say "  env-file wrote: $(cat "$ENVF" 2>/dev/null)"
  say "  exit=$RC elapsed=${ELAPSED}s"
  [ -z "$OUT" ] || printf '%s\n' "$OUT" | sed "s/^/[$LABEL]   | /" | head -20
}

# On a hang, show the nested wrapper processes, then stop every process under WORK.
snapshot_and_reap() {
  [ "$RC" = 124 ] || return 0
  case $OS in
  MINGW* | MSYS* | CYGWIN*)
    local winwork
    winwork=$(cygpath -w "$WORK")
    say "  timed out: Windows processes whose command line names this lab's hooks dir:"
    powershell.exe -NoProfile -Command "\$w='$winwork'; Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -and \$_.CommandLine.Contains(\$w) } | ForEach-Object { '{0} parent={1} {2}' -f \$_.ProcessId,\$_.ParentProcessId,\$_.CommandLine }" 2>&1 | tr -d '\r' | head -15 | sed "s/^/[$LABEL]   ps | /"
    local n
    n=$(powershell.exe -NoProfile -Command "\$w='$winwork'; @(Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -and \$_.CommandLine.Contains(\$w) -and \$_.CommandLine.Contains('pre-commit') }).Count" 2>/dev/null | tr -d '\r')
    say "  pre-commit wrapper processes alive after the timeout: $n"
    powershell.exe -NoProfile -Command "\$w='$winwork'; Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -and \$_.CommandLine.Contains(\$w) } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
    ;;
  *)
    say "  timed out: processes running this lab's hooks:"
    ps -ef 2>/dev/null | grep -F "$WORK" | grep -v grep | head -15 | sed "s/^/[$LABEL]   ps | /"
    pkill -f "$WORK" 2>/dev/null
    ;;
  esac
}

teardown() {
  chmod -R u+w "$WORK" 2>/dev/null
  rm -rf "$WORK"
}

count_tag() { grep -c "^$1 " "$LOG" 2>/dev/null; }

# A: worker commit with a Cursor co-author trailer through the pane env channel.
scenario_commit() {
  say "=== scenario commit: git commit in the worker pane (project pre-commit + commit-msg hooks present) ==="
  setup
  marker_hook "$REPO/.git/hooks/pre-commit" project-pre-commit "$LOG"
  marker_hook "$REPO/.git/hooks/commit-msg" project-commit-msg "$LOG"
  install_wrappers || { teardown; return; }
  printf 'more\n' >>"$REPO/README.md"
  git -C "$REPO" add README.md
  pane "git commit -q --trailer 'Co-authored-by: Cursor <cursoragent@cursor.com>' --trailer 'Co-authored-by: Jane Human <jane@example.com>' -m 'fix: windows hook wrapper'"
  snapshot_and_reap
  local body
  body=$(git -C "$REPO" log -1 --format=%B)
  say "  HEAD message: $(printf '%s' "$body" | tr '\n' '|')"
  say "  project hook log:"; sed "s/^/[$LABEL]   log | /" "$LOG" | head -8
  if [ "$RC" = 0 ]; then ok "commit returned (exit 0, ${ELAPSED}s)"; else bad "commit did not complete (exit $RC after ${ELAPSED}s)"; fi
  case $body in *'Co-authored-by: Cursor'*) bad "Cursor trailer reached the commit object" ;; *'fix: windows hook wrapper'*) ok "Cursor trailer stripped" ;; *) bad "commit object missing" ;; esac
  case $body in *'Co-authored-by: Jane Human <jane@example.com>'*) ok "human co-author trailer kept" ;; *) bad "human trailer missing" ;; esac
  [ "$(count_tag project-pre-commit)" = 1 ] && ok "project pre-commit ran exactly once" || bad "project pre-commit ran $(count_tag project-pre-commit) times"
  [ "$(count_tag project-commit-msg)" = 1 ] && ok "project commit-msg ran exactly once" || bad "project commit-msg ran $(count_tag project-commit-msg) times"
  teardown
}

# B: worker push through the pre-push wrapper to a local bare remote.
scenario_push() {
  say "=== scenario push: git push from the worker pane (project pre-push hook present) ==="
  setup
  marker_hook "$REPO/.git/hooks/pre-push" project-pre-push "$LOG"
  install_wrappers || { teardown; return; }
  pane "git push -q origin HEAD:refs/heads/fm/task-1"
  snapshot_and_reap
  say "  project hook log:"; sed "s/^/[$LABEL]   log | /" "$LOG" | head -5
  if [ "$RC" = 0 ]; then ok "push returned (exit 0, ${ELAPSED}s)"; else bad "push did not complete (exit $RC after ${ELAPSED}s)"; fi
  [ "$(git -C "$WORK/origin.git" rev-parse --verify -q refs/heads/fm/task-1)" = "$(git -C "$REPO" rev-parse HEAD)" ] && ok "remote has fm/task-1 at HEAD" || bad "remote branch missing"
  [ "$(count_tag project-pre-push)" = 1 ] && ok "project pre-push ran exactly once" || bad "project pre-push ran $(count_tag project-pre-push) times"
  teardown
}

# C (adversarial): repo config points core.hooksPath at a sibling dir whose name extends
# ours, written in the native spelling. It is NOT ours, so the wrapper must chain it.
scenario_foreign() {
  say "=== scenario foreign-hooks-dir: repo core.hooksPath = sibling '<ours>-husky' in native spelling ==="
  setup
  local other="$HOOKS-husky" spelled
  marker_hook "$other/pre-commit" foreign-pre-commit "$LOG"
  marker_hook "$REPO/.git/hooks/pre-commit" default-dir-pre-commit "$LOG"
  spelled=$other
  command -v cygpath >/dev/null 2>&1 && spelled=$(cygpath -m -- "$other")
  git -C "$REPO" config core.hooksPath "$spelled"
  say "  repo core.hooksPath=$(git -C "$REPO" config core.hooksPath)"
  install_wrappers || { teardown; return; }
  printf 'x\n' >>"$REPO/README.md"
  git -C "$REPO" add README.md
  pane "git commit -q -m 'chore: foreign hooks dir'"
  snapshot_and_reap
  say "  project hook log:"; sed "s/^/[$LABEL]   log | /" "$LOG" | head -5
  if [ "$RC" = 0 ]; then ok "commit returned (exit 0, ${ELAPSED}s)"; else bad "commit failed (exit $RC)"; fi
  [ "$(count_tag foreign-pre-commit)" = 1 ] && ok "foreign hooks dir's pre-commit ran exactly once (not mistaken for ours)" || bad "foreign pre-commit ran $(count_tag foreign-pre-commit) times"
  [ "$(count_tag default-dir-pre-commit)" = 0 ] && ok ".git/hooks pre-commit correctly not run" || bad ".git/hooks pre-commit ran unexpectedly"
  teardown
}

# D (adversarial): an inherited GIT_CONFIG entry with a path-like value must survive
# for the project's hook while only our core.hooksPath entry is removed.
scenario_inherited() {
  say "=== scenario inherited-config: pane already carries GIT_CONFIG fmtest.inherited=<posix path> ==="
  setup
  marker_hook "$REPO/.git/hooks/pre-commit" project-pre-commit "$LOG"
  install_wrappers || { teardown; return; }
  printf 'y\n' >>"$REPO/README.md"
  git -C "$REPO" add README.md
  local inherited="$WORK/state"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=fmtest.inherited GIT_CONFIG_VALUE_0="$inherited"
  pane "git commit -q -m 'chore: inherited config'"
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
  snapshot_and_reap
  say "  project hook log:"; sed "s/^/[$LABEL]   log | /" "$LOG" | head -5
  if [ "$RC" = 0 ]; then ok "commit returned (exit 0, ${ELAPSED}s)"; else bad "commit failed (exit $RC)"; fi
  local line
  line=$(grep '^project-pre-commit ' "$LOG" | head -1)
  case $line in *'GIT_CONFIG_COUNT=1 KEY_0=fmtest.inherited'*) ok "project hook saw only the inherited entry (our hooksPath entry removed)" ;; *) bad "unexpected GIT_CONFIG in project hook: $line" ;; esac
  case $line in *"inherited="?*) ok "project hook still reads fmtest.inherited through git config" ;; *) bad "inherited entry lost" ;; esac
  [ "$(count_tag project-pre-commit)" = 1 ] && ok "project pre-commit ran exactly once" || bad "project pre-commit ran $(count_tag project-pre-commit) times"
  teardown
}

# E: repo with no hooks of its own - the wrapper must find none and finish.
scenario_nohooks() {
  say "=== scenario no-project-hooks: commit + push with an empty .git/hooks ==="
  setup
  rm -rf "$REPO/.git/hooks"/*
  install_wrappers || { teardown; return; }
  printf 'z\n' >>"$REPO/README.md"
  git -C "$REPO" add README.md
  pane "git commit -q --trailer 'Co-authored-by: Cursor <cursoragent@cursor.com>' -m 'chore: no hooks' && git push -q origin HEAD:refs/heads/fm/task-1"
  snapshot_and_reap
  if [ "$RC" = 0 ]; then ok "commit+push returned (exit 0, ${ELAPSED}s)"; else bad "commit+push did not complete (exit $RC after ${ELAPSED}s)"; fi
  case $(git -C "$REPO" log -1 --format=%B) in *Cursor*) bad "trailer survived" ;; *) ok "Cursor trailer stripped" ;; esac
  teardown
}

# F: cost of one commit with and without the wrappers on this host (context for slow hosts).
scenario_timing() {
  say "=== scenario timing: same commit with no wrappers vs through the pane wrappers ==="
  setup
  local t0=$SECONDS
  printf 't
' >>"$REPO/README.md"; git -C "$REPO" add README.md
  git -C "$REPO" commit -q -m 'chore: plain' && say "  plain git commit (no wrappers): $((SECONDS - t0))s"
  install_wrappers || { teardown; return; }
  printf 'u
' >>"$REPO/README.md"; git -C "$REPO" add README.md
  pane "git commit -q -m 'chore: wrapped'"
  [ "$RC" = 0 ] && ok "wrapped commit returned in ${ELAPSED}s" || bad "wrapped commit exit $RC"
  teardown
}

say "os=$OS git=$(git --version) cygpath=$(command -v cygpath || echo none) bin=$BIN"
for s in "$@"; do "scenario_$s"; done
say "TOTAL FAILURES: $fails"
exit "$fails"
