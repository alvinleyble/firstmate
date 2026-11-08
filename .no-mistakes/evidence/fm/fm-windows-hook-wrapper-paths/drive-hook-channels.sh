#!/usr/bin/env bash
# Adversarial channels for the per-task hook wrapper on native Windows Git Bash
# (real git.exe, real cygpath). For each case: install + env-file the way
# bin/fm-spawn.sh does, source it in a pane shell, then commit with an AI
# trailer under a timeout.
#   repo-config-<form>  the repository's own config names this launch's hooks
#                       dir in a Windows spelling (a hook manager writing it):
#                       the wrapper must see it as its own and stop, not loop.
#   git-c               git -c core.hooksPath=<ours> (GIT_CONFIG_PARAMETERS):
#                       the project's hook must still run exactly once.
#   other-repo          git -C <another repo> from the task pane: that repo's
#                       own hook runs, not the task worktree's.
# Usage: drive-hook-channels.sh <fm-bin-dir> <scratch-root>
set -u
FMBIN=$1 BASE=$2
STRIP="$FMBIN/fm-git-strip-ai-trailers.sh"
LIMIT=${FM_DRIVE_LIMIT:-40}
mkrepo() { # <dir> <log>
  git init -q -b main "$1"
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name tester
  echo hi >"$1/README.md"
  git -C "$1" add README.md
  git -C "$1" commit -q -m init
  cat >"$1/.git/hooks/pre-commit" <<SH
#!/usr/bin/env bash
echo "pre-commit of ${1##*/} ran" >>'$2'
SH
  chmod +x "$1/.git/hooks/pre-commit"
}
reap() { # <tag>
  local f pid n=0
  for f in /proc/[0-9]*/cmdline; do
    pid=${f#/proc/}; pid=${pid%/cmdline}
    if { tr '\0' ' ' <"$f" | grep -q "$1"; } 2>/dev/null; then kill -9 "$pid" 2>/dev/null && n=$((n + 1)); fi
  done
  echo "$n"
}
for case in repo-config-mixed repo-config-backslash repo-config-lowerdrive git-c other-repo; do
  ROOT="$BASE/ch-$case"
  rm -rf "$ROOT"; mkdir -p "$ROOT/state" "$ROOT/launch"
  ROOT=$(cd "$ROOT" && pwd -P)
  WT="$ROOT/wt" OTHER="$ROOT/other" HOOKS="$ROOT/state/t.git-hooks" ENVF="$ROOT/launch/git-config.sh" LOG="$ROOT/hooks.log"
  mkrepo "$WT" "$LOG"; mkrepo "$OTHER" "$LOG"
  "$STRIP" install "$HOOKS" "$WT" >/dev/null || { echo "[$case] install failed"; continue; }
  case $case in
  repo-config-mixed) git -C "$WT" config core.hooksPath "$(cygpath -m "$HOOKS")" ;;
  repo-config-backslash) git -C "$WT" config core.hooksPath "$(cygpath -w "$HOOKS")" ;;
  repo-config-lowerdrive) w=$(cygpath -m "$HOOKS"); git -C "$WT" config core.hooksPath "$(printf '%s' "${w:0:1}" | tr '[:upper:]' '[:lower:]')${w:1}" ;;
  esac
  target=$WT gitc=
  [ "$case" = other-repo ] && target=$OTHER
  [ "$case" = git-c ] && gitc="-c core.hooksPath=$HOOKS"
  echo "== [$case] hooks dir: $HOOKS"
  [ -z "$(git -C "$WT" config --get core.hooksPath)" ] || echo "   repo config core.hooksPath = $(git -C "$WT" config --get core.hooksPath)"
  echo note >>"$target/README.md"; git -C "$target" add README.md
  out=$(env -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS bash --noprofile --norc -c "
    '$STRIP' env-file '$HOOKS' '$ENVF' && . '$ENVF' || exit 1
    s=\$SECONDS
    timeout -k 2 $LIMIT git $gitc -C '$target' commit -q -m 'fix: $case' --trailer 'Co-authored-by: Claude <noreply@anthropic.com>'
    echo \"git commit exit=\$? after \$((SECONDS - s))s\"" 2>&1 </dev/null)
  printf '%s\n' "$out" | sed 's/^/   pane| /'
  echo "   looping wrappers reaped: $(reap "ch-$case/state/t.git-hooks")"
  echo "   project hooks run: $(tr '\n' ';' <"$LOG" 2>/dev/null)"
  echo "   HEAD message of ${target##*/}: $(git -C "$target" log -1 --format=%B | tr '\n' '|')"
done
