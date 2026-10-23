#!/usr/bin/env bash
# Secondmate inheritance of config/merge-passphrases through the real
# bin/fm-config-push.sh, then a real Forgejo merge from the secondmate home.
set -uo pipefail
TOKEN=$(cat /lab/token); API=http://localhost:3000/api/v1; REPO=fixture/fixture-repo
WORD_A=lab-word-staging
digest() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
auth=(-H "Authorization: token $TOKEN" -H 'Content-Type: application/json')
W=/lab/cp; rm -rf "$W"; mkdir -p "$W/home/state" "$W/home/data" "$W/home/config"
git config --global user.email fixture@example.invalid; git config --global user.name fixture
git config --global --add safe.directory '*'
git init -q -b main "$W/main"; cp /fm/AGENTS.md /fm/.gitignore "$W/main/"; cp -r /fm/bin "$W/main/bin"; git -C "$W/main" add -A; git -C "$W/main" commit -qm c1
git -C "$W/main" worktree add -q --detach "$W/alpha" HEAD
printf 'alpha\n' > "$W/alpha/.fm-secondmate-home"
printf '%s\n' "window=firstmate:fm-alpha" "kind=secondmate" "home=$W/alpha" > "$W/home/state/alpha.meta"
export FM_HOME="$W/home" FM_ROOT_OVERRIDE="$W/main" FM_SEND_SETTLE=0 TMUX_TMPDIR=/lab/tmux
mkdir -p /lab/tmux; tmux kill-server 2>/dev/null; tmux new-session -d -s firstmate -n fm-alpha bash
show_instr() { local f; f=$(ls -t "$W/alpha/state"/.fm-inherited-config-reread* 2>/dev/null | head -1); if [ -n "$f" ]; then echo "newest reread instruction: ${f#$W/}"; sed 's/^/    > /' "$f"; else echo "no reread instruction file in the secondmate home"; fi; }

echo "=== P1 primary gains config/merge-passphrases; secondmate has none"
printf '%s\n' "* staging sha256:$(digest "$WORD_A")" > "$W/home/config/merge-passphrases"
echo "\$ bin/fm-config-push.sh"; /fm/bin/fm-config-push.sh 2>&1 | grep -v 'watcher' | sed 's/^/  | /'; echo "exit=${PIPESTATUS[0]}"
cmp "$W/home/config/merge-passphrases" "$W/alpha/config/merge-passphrases" && echo "secondmate config/merge-passphrases is byte-identical to the primary's"
ls "$W/alpha/state"/.fm-inherited-config-reread* >/dev/null 2>&1 && echo "UNEXPECTED: a reread instruction was written" || echo "no reread instruction written for a merge-passphrases-only change"
echo "tmux keys sent to fm-alpha: $(tmux capture-pane -p -t firstmate:fm-alpha | grep -c CONFIG_REREAD) CONFIG_REREAD lines"

echo; echo "=== P2 a merge performed FROM the secondmate home into gated 'staging' needs the captain's word"
cd /lab/src && git fetch -q origin && git checkout -q -B feat-sm-$$ origin/main && echo sm > feat-sm-$$.txt && git add . && git commit -qm sm && git push -q -f origin feat-sm-$$ 2>/dev/null
sha=$(git rev-parse HEAD); cd /
n=$(curl -sf "${auth[@]}" -X POST "$API/repos/$REPO/pulls" -d '{"head":"feat-sm-$$","base":"staging","title":"P2 secondmate merge"}' | jq -r .number)
curl -sf "${auth[@]}" -X POST "$API/repos/$REPO/statuses/$sha" -d '{"state":"success","context":"fmlab/ci"}' >/dev/null
for i in $(seq 1 20); do [ "$(curl -sf "${auth[@]}" "$API/repos/$REPO/pulls/$n" | jq -r .mergeable)" = true ] && break; sleep 2; done
cp /lab/home/.tasks.toml "$W/alpha/.tasks.toml"; mkdir -p "$W/alpha/data"; printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$W/alpha/data/backlog.md"
git clone -q "http://fixture:$TOKEN@localhost:3000/$REPO.git" /lab/wt/sm 2>/dev/null || true
printf '%s\n' "window=fm-sm-t1" "worktree=/lab/wt/sm" "project=/lab/project" "kind=ship" "mode=no-mistakes" > "$W/alpha/state/sm-t1.meta"
for args in "" "--passphrase $WORD_A"; do
  echo "\$ FM_HOME=<secondmate alpha> bin/fm-pr-merge.sh sm-t1 https://localhost/$REPO/pulls/$n ${args:+--passphrase <word-A>}"
  (unset FM_ROOT_OVERRIDE; HOME=/lab/teahome XDG_CONFIG_HOME=/lab/teahome/.config FM_HOME="$W/alpha" /fm/bin/fm-pr-merge.sh sm-t1 "https://localhost/$REPO/pulls/$n" $args) > /lab/out 2>&1; rc=$?
  grep -v 'watcher\|●\|queued wakes' /lab/out | sed 's/^/  | /'; echo "exit=$rc"
  grep -qF "$WORD_A" /lab/out || grep -qF "$(digest "$WORD_A")" /lab/out && echo LEAK || echo "leak-check: no passphrase word or digest in output"
  curl -sf "${auth[@]}" "$API/repos/$REPO/pulls/$n" | jq -r '"forge: PR #\(.number) state=\(.state) merged=\(.merged) base=\(.base.ref)"'
done

echo; echo "=== P3 primary changes crew-harness AND merge-passphrases together"
printf 'codex\n' > "$W/home/config/crew-harness"
printf '%s\n' "* staging sha256:$(digest "$WORD_A")" "* main sha256:$(digest other-word)" > "$W/home/config/merge-passphrases"
echo "\$ bin/fm-config-push.sh"; /fm/bin/fm-config-push.sh 2>&1 | grep -v 'watcher' | sed 's/^/  | /'; echo "exit=${PIPESTATUS[0]}"
cmp "$W/home/config/merge-passphrases" "$W/alpha/config/merge-passphrases" && echo "secondmate config/merge-passphrases converged byte-identical"
show_instr
f=$(ls -t "$W/alpha/state"/.fm-inherited-config-reread* 2>/dev/null | head -1)
if [ -n "$f" ] && grep -q 'crew-harness' "$f" && ! grep -q 'merge-passphrases\|sha256:' "$f"; then echo "reread instruction names crew-harness only; no merge-passphrases path or sha256 digest inlined"; else echo "UNEXPECTED: reread instruction missing or inlines merge-passphrases"; fi

echo; echo "=== P4 primary removes config/merge-passphrases"
rm -f "$W/home/config/merge-passphrases"
before=$(ls "$W/alpha/state"/.fm-inherited-config-reread* 2>/dev/null | wc -l)
echo "\$ bin/fm-config-push.sh"; /fm/bin/fm-config-push.sh 2>&1 | grep -v 'watcher' | sed 's/^/  | /'; echo "exit=${PIPESTATUS[0]}"
[ -e "$W/alpha/config/merge-passphrases" ] && echo "UNEXPECTED: secondmate copy survived" || echo "secondmate config/merge-passphrases removed (primary absence mirrored; secondmate now ungated)"
after=$(ls "$W/alpha/state"/.fm-inherited-config-reread* 2>/dev/null | wc -l)
echo "reread instruction files before=$before after=$after (no new reread for a merge-passphrases-only removal)"
tmux kill-server 2>/dev/null
