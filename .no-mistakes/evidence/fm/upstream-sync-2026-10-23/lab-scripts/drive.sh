#!/usr/bin/env bash
# Drive the real bin/fm-pr-merge.sh (read-only worktree at /fm) against the
# disposable Forgejo at localhost:3000 with a disposable FM_HOME at /lab/home.
set -uo pipefail
TOKEN=$(cat /lab/token)
API=http://localhost:3000/api/v1
HOST=localhost
REPO=fixture/fixture-repo
WORD_A=lab-word-staging
WORD_B=lab-word-other
digest() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
export HOME=/lab/teahome XDG_CONFIG_HOME=/lab/teahome/.config FM_HOME=/lab/home
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_MERGE_PASSPHRASE

rm -rf /lab/home /lab/wt; mkdir -p /lab/home/config /lab/home/data /lab/home/state /lab/wt
cat > /lab/home/.tasks.toml <<'TOML'
backend = "markdown"

[markdown]
path = "data/backlog.md"
archive = "data/done-archive.md"
done_keep = 10
TOML
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > /lab/home/data/backlog.md
for n in 1 2 3 4 5 6 7; do
  git clone -q "http://fixture:$TOKEN@localhost:3000/$REPO.git" "/lab/wt/t$n" 2>/dev/null
  printf '%s\n' "window=fm-lab-t$n" "worktree=/lab/wt/t$n" "project=/lab/project" "kind=ship" "mode=no-mistakes" \
    > "/lab/home/state/lab-t$n.meta"
done

pass_file() { : > /lab/home/config/merge-passphrases; for l in "$@"; do printf '%s\n' "$l" >> /lab/home/config/merge-passphrases; done; }
pr_state() {  # <n>
  curl -sf -H "Authorization: token $TOKEN" "$API/repos/$REPO/pulls/$1" \
    | jq -r '"forge: PR #\(.number) state=\(.state) merged=\(.merged) base=\(.base.ref) head=\(.head.ref)"'
}
leak_check() {  # <file>
  local w hit=0
  for w in "$WORD_A" "$WORD_B" "$(digest "$WORD_A")" "$(digest "$WORD_B")"; do
    grep -qF "$w" "$1" && { echo "LEAK: output contains a passphrase or digest"; hit=1; }
  done
  [ "$hit" = 0 ] && echo "leak-check: no passphrase word or digest in output"
}
run() {  # <label> <n> [env-assignments --] args...
  local label=$1 n=$2 rc; shift 2
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "::" ]; do envs+=("$1"); shift; done
  shift
  echo
  echo "=== $label"
  echo "\$ ${envs[*]:+${envs[*]} }bin/fm-pr-merge.sh lab-t$n https://$HOST/$REPO/pulls/$n $*" | sed "s/$WORD_A/<word-A>/g; s/$WORD_B/<word-B>/g"
  env "${envs[@]}" /fm/bin/fm-pr-merge.sh "lab-t$n" "https://$HOST/$REPO/pulls/$n" "$@" > /lab/out 2>&1
  rc=$?
  sed 's/^/  | /' /lab/out
  echo "exit=$rc"
  leak_check /lab/out
  pr_state "$n"
}

echo "### merge-passphrases gate vs a real Forgejo $(curl -s $API/version | jq -r .version), tea $(tea --version | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}')"
echo "### worktree commit: $(git -C /fm rev-parse HEAD 2>/dev/null || echo unknown)"

pass_file "* staging sha256:$(digest "$WORD_A")"
echo; echo "config/merge-passphrases (digest elided): * staging sha256:<digest of word-A>"
run "S1 gated base 'staging', no passphrase -> refuse, PR stays open" 1 ::
run "S2 gated base 'staging', wrong passphrase -> refuse, PR stays open" 1 :: --passphrase "$WORD_B"
run "S3 gated base 'staging', matching --passphrase -> merged" 1 :: --passphrase "$WORD_A"
run "S4 gated base 'staging', matching FM_MERGE_PASSPHRASE -> merged" 2 FM_MERGE_PASSPHRASE="$WORD_A" ::
run "S5 ungated base 'dev', no passphrase -> merged" 3 ::

echo; echo "=== S7 retarget PR #4 from 'dev' to gated 'staging' on the forge (nothing local records the base)"
curl -sf -H "Authorization: token $TOKEN" -H 'Content-Type: application/json' -X PATCH "$API/repos/$REPO/pulls/4" -d '{"base":"staging"}' >/dev/null
pr_state 4
run "S7a PR #4 now targets 'staging' live, no passphrase -> refuse" 4 ::
run "S7b PR #4, matching passphrase -> merged into staging" 4 :: --passphrase "$WORD_A"

run "S6a wrapup pre-fix form on Forgejo (--attended-override -- --delete-branch) -> refused by Forgejo arg filter" 5 :: --attended-override -- --delete-branch
run "S6b wrapup forge-aware form for Forgejo (--passphrase <word> -- --merge, no deletion args) -> merged" 5 :: --passphrase "$WORD_A" -- --merge
echo "forge branch feat-wrapup after merge: $(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token $TOKEN" "$API/repos/$REPO/branches/feat-wrapup") (200 = still on the forge, left for the captain per the wrapup skill)"

pass_file "* staging not-a-digest"
echo; echo "config/merge-passphrases: * staging not-a-digest"
run "S8a malformed file -> every merge refused, even into ungated 'dev'" 6 ::
pass_file "* staging sha256:$(digest "$WORD_A")"
run "S8b file fixed -> ungated 'dev' merges again" 6 ::

pass_file "* staging sha256:$(digest "$WORD_A")" "Fixture/Fixture-Repo staging sha256:$(digest "$WORD_B")"
echo; echo "config/merge-passphrases (digests elided): '* staging <word-A>' and 'Fixture/Fixture-Repo staging <word-B>'"
run "S9a repository line (case-insensitive) beats '*': word-A -> refuse" 7 :: --passphrase "$WORD_A"
run "S9b repository line word-B -> merged" 7 :: --passphrase "$WORD_B"

echo; echo "=== recorded task meta after merges (pr= recorded by fm-pr-check)"
grep -H '^pr=' /lab/home/state/lab-t*.meta
