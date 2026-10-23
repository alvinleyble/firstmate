#!/usr/bin/env bash
# Disposable Forgejo fixture: repo fixture/fixture-repo, bases main/staging/dev,
# one feature branch + PR per scenario, each head with a success commit status.
set -euo pipefail
TOKEN=$(cat /lab/token)
API=http://localhost:3000/api/v1
auth=(-H "Authorization: token $TOKEN" -H 'Content-Type: application/json')
curl -sf "${auth[@]}" -X POST "$API/user/repos" \
  -d '{"name":"fixture-repo","auto_init":true,"default_branch":"main","readme":"Default"}' >/dev/null
# Forgejo answers default_merge_style; keep the repository default (merge).
rm -rf /lab/src && git clone -q "http://fixture:$TOKEN@localhost:3000/fixture/fixture-repo.git" /lab/src
cd /lab/src
git config user.email fixture@example.invalid; git config user.name fixture
git push -q origin main:staging main:dev
mk_pr() {  # <branch> <base> <title>
  git checkout -q -B "$1" origin/main
  printf '%s\n' "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$3"
  git push -q -f origin "$1"
  local sha num
  sha=$(git rev-parse HEAD)
  num=$(curl -sf "${auth[@]}" -X POST "$API/repos/fixture/fixture-repo/pulls" \
    -d "{\"head\":\"$1\",\"base\":\"$2\",\"title\":\"$3\"}" | jq -r .number)
  curl -sf "${auth[@]}" -X POST "$API/repos/fixture/fixture-repo/statuses/$sha" \
    -d '{"state":"success","context":"fmlab/ci","description":"lab green"}' >/dev/null
  printf '%s %s %s %s\n' "$num" "$1" "$2" "$sha"
}
git fetch -q origin
mk_pr feat-gated-flag   staging "S1-3 gated by flag"
mk_pr feat-gated-env    staging "S4 gated by env"
mk_pr feat-ungated      dev     "S5 ungated base"
mk_pr feat-retarget     dev     "S7 retargeted to gated base"
mk_pr feat-wrapup       staging "S6 wrapup command shape"
mk_pr feat-malformed    dev     "S8 malformed passphrase file"
mk_pr feat-repo-line    staging "S9 repository line beats star"
