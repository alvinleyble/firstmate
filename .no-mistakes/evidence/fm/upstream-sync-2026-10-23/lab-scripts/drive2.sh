#!/usr/bin/env bash
# Re-drive S4 (FM_MERGE_PASSPHRASE) after Forgejo finished re-checking PR #2's
# mergeability against the moved 'staging' base, plus flag-over-env precedence.
set -uo pipefail
TOKEN=$(cat /lab/token); API=http://localhost:3000/api/v1; HOST=localhost; REPO=fixture/fixture-repo
WORD_A=lab-word-staging; WORD_B=lab-word-other
digest() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
export HOME=/lab/teahome XDG_CONFIG_HOME=/lab/teahome/.config FM_HOME=/lab/home
unset FM_MERGE_PASSPHRASE
auth=(-H "Authorization: token $TOKEN" -H 'Content-Type: application/json')
pr_state() { curl -sf "${auth[@]}" "$API/repos/$REPO/pulls/$1" | jq -r '"forge: PR #\(.number) state=\(.state) merged=\(.merged) mergeable=\(.mergeable) base=\(.base.ref) head=\(.head.ref)"'; }
leak_check() { local w hit=0; for w in "$WORD_A" "$WORD_B" "$(digest "$WORD_A")" "$(digest "$WORD_B")"; do grep -qF "$w" "$1" && { echo "LEAK"; hit=1; }; done; [ "$hit" = 0 ] && echo "leak-check: no passphrase word or digest in output"; }
run() {
  local label=$1 n=$2 rc; shift 2; local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "::" ]; do envs+=("$1"); shift; done; shift
  echo; echo "=== $label"
  echo "\$ ${envs[*]:+${envs[*]} }bin/fm-pr-merge.sh lab-t$n https://$HOST/$REPO/pulls/$n $*" | sed "s/$WORD_A/<word-A>/g; s/$WORD_B/<word-B>/g"
  env "${envs[@]}" /fm/bin/fm-pr-merge.sh "lab-t$n" "https://$HOST/$REPO/pulls/$n" "$@" > /lab/out 2>&1; rc=$?
  grep -v 'WARNING: queued wakes pending' /lab/out | sed 's/^/  | /'; echo "exit=$rc"; leak_check /lab/out; pr_state "$n"
}
# A fresh PR for the precedence case.
cd /lab/src && git fetch -q origin && git checkout -q -B feat-precedence origin/main
echo precedence > feat-precedence.txt && git add feat-precedence.txt && git commit -qm "S4c precedence" && git push -q -f origin feat-precedence 2>/dev/null
sha=$(git rev-parse HEAD)
curl -sf "${auth[@]}" -X POST "$API/repos/$REPO/pulls" -d '{"head":"feat-precedence","base":"staging","title":"S4c flag beats env"}' | jq -r '"created PR #\(.number)"'
curl -sf "${auth[@]}" -X POST "$API/repos/$REPO/statuses/$sha" -d '{"state":"success","context":"fmlab/ci"}' >/dev/null
git clone -q "http://fixture:$TOKEN@localhost:3000/$REPO.git" /lab/wt/t8 2>/dev/null || true
printf '%s\n' "window=fm-lab-t8" "worktree=/lab/wt/t8" "project=/lab/project" "kind=ship" "mode=no-mistakes" > /lab/home/state/lab-t8.meta
printf '%s\n' "* staging sha256:$(digest "$WORD_A")" > /lab/home/config/merge-passphrases
echo "config/merge-passphrases (digest elided): * staging sha256:<digest of word-A>"
for i in $(seq 1 20); do [ "$(curl -sf "${auth[@]}" "$API/repos/$REPO/pulls/2" | jq -r .mergeable)" = true ] && [ "$(curl -sf "${auth[@]}" "$API/repos/$REPO/pulls/8" | jq -r .mergeable)" = true ] && break; sleep 2; done
pr_state 2; pr_state 8
run "S4a gated 'staging', wrong FM_MERGE_PASSPHRASE -> refuse" 2 FM_MERGE_PASSPHRASE="$WORD_B" ::
run "S4b gated 'staging', matching FM_MERGE_PASSPHRASE -> merged" 2 FM_MERGE_PASSPHRASE="$WORD_A" ::
run "S4c wrong FM_MERGE_PASSPHRASE but matching --passphrase -> flag wins, merged" 8 FM_MERGE_PASSPHRASE="$WORD_B" :: --passphrase "$WORD_A"
