#!/usr/bin/env bash
# P2: the gate inherited through fm-config-push gates a merge run FROM the
# secondmate home (FM_HOME=secondmate) against the real Forgejo.
set -uo pipefail
TOKEN=$(cat /lab/token); API=http://localhost:3000/api/v1; REPO=fixture/fixture-repo
WORD_A=lab-word-staging
digest() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
auth=(-H "Authorization: token $TOKEN" -H 'Content-Type: application/json')
W=/lab/cp
export TMUX_TMPDIR=/lab/tmux FM_SEND_SETTLE=0
printf '%s\n' "* staging sha256:$(digest "$WORD_A")" > "$W/home/config/merge-passphrases"
echo "=== P2 primary re-gains config/merge-passphrases ('* staging <word-A>'); push to secondmate alpha"
echo "\$ bin/fm-config-push.sh"
FM_HOME="$W/home" FM_ROOT_OVERRIDE="$W/main" /fm/bin/fm-config-push.sh 2>&1 | grep 'merge-passphrases\|config-reread\|secondmate alpha' | sed 's/^/  | /'
cmp -s "$W/home/config/merge-passphrases" "$W/alpha/config/merge-passphrases" && echo "secondmate copy byte-identical"
br=feat-sm-p2
cd /lab/src && git fetch -q origin && git checkout -q -B "$br" origin/main && echo sm > "$br.txt" && git add . && git commit -qm "P2 secondmate merge" && git push -q -f origin "$br" 2>/dev/null
sha=$(git rev-parse HEAD); cd /
n=$(curl -sf "${auth[@]}" -X POST "$API/repos/$REPO/pulls" -d "$(jq -nc --arg h "$br" '{head:$h,base:"staging",title:"P2 secondmate merge"}')" | jq -r .number)
curl -sf "${auth[@]}" -X POST "$API/repos/$REPO/statuses/$sha" -d '{"state":"success","context":"fmlab/ci"}' >/dev/null
for i in $(seq 1 20); do [ "$(curl -sf "${auth[@]}" "$API/repos/$REPO/pulls/$n" | jq -r .mergeable)" = true ] && break; sleep 2; done
echo "created PR #$n ($br -> staging) with a green status"
cp /lab/home/.tasks.toml "$W/alpha/.tasks.toml"; mkdir -p "$W/alpha/data" "$W/alpha/state"
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$W/alpha/data/backlog.md"
rm -rf /lab/wt/sm; git clone -q "http://fixture:$TOKEN@localhost:3000/$REPO.git" /lab/wt/sm 2>/dev/null
printf '%s\n' "window=fm-sm-t1" "worktree=/lab/wt/sm" "project=/lab/project" "kind=ship" "mode=no-mistakes" > "$W/alpha/state/sm-t1.meta"
for args in "" "--passphrase $WORD_A"; do
  echo; echo "\$ FM_HOME=/lab/cp/alpha bin/fm-pr-merge.sh sm-t1 https://localhost/$REPO/pulls/$n ${args:+--passphrase <word-A>}"
  (HOME=/lab/teahome XDG_CONFIG_HOME=/lab/teahome/.config FM_HOME="$W/alpha" /fm/bin/fm-pr-merge.sh sm-t1 "https://localhost/$REPO/pulls/$n" $args) > /lab/out 2>&1; rc=$?
  grep -v 'watcher\|●\|queued wakes' /lab/out | sed 's/^/  | /'; echo "exit=$rc"
  if grep -qF "$WORD_A" /lab/out || grep -qF "$(digest "$WORD_A")" /lab/out; then echo LEAK; else echo "leak-check: no passphrase word or digest in output"; fi
  curl -sf "${auth[@]}" "$API/repos/$REPO/pulls/$n" | jq -r '"forge: PR #\(.number) state=\(.state) merged=\(.merged) base=\(.base.ref)"'
done
