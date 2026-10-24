make_case() {
  local name=$1 dir fakebin fake_root
  dir="$TMP_ROOT/$name"
  fakebin="$dir/fakebin"
  fake_root="$dir/root"
  mkdir -p "$dir/home/state" "$dir/home/data" "$dir/home/config" "$dir/wt" "$fakebin" "$fake_root/bin"
  git -C "$dir/wt" init -q
  git -C "$dir/wt" commit -q --allow-empty -m init
  git -C "$dir/wt" update-ref refs/remotes/origin/main "$(git -C "$dir/wt" rev-parse HEAD)"
  cat > "$fake_root/bin/fm-guard.sh" <<'SH'
#!/usr/bin/env bash
printf 'guard\n' >> "$FM_TEST_GUARD_LOG"
SH
  chmod +x "$fake_root/bin/fm-guard.sh"
  cat > "$fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_LOG"
case "${1:-} ${2:-}" in
  "api graphql")
    printf '%s\n' \
      "state=${FM_TEST_GH_GRAPHQL_STATE:-MERGED}" \
      "merged=${FM_TEST_GH_GRAPHQL_MERGED:-true}" \
      "queued=${FM_TEST_GH_GRAPHQL_QUEUED:-false}" \
      'base=main'
    exit 0
    ;;
  "pr view")
    case " $* " in
      *statusCheckRollup*)
        printf '%s\n' "{\"state\":\"OPEN\",\"isDraft\":false,\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"headRefOid\":\"${FM_TEST_GH_HEAD:-0123456789abcdef0123456789abcdef01234567}\",\"baseRefName\":\"main\",\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]}"
        exit 0
        ;;
      *" --json isDraft "*)
        printf '%s\n' "{\"isDraft\":${FM_TEST_GH_DRAFT:-false}}"
        exit 0
        ;;
      *headRefOid,reviewDecision*)
        printf '%s\n' "{\"headRefOid\":\"${FM_TEST_GH_HEAD:-0123456789abcdef0123456789abcdef01234567}\",\"reviewDecision\":\"APPROVED\"}"
        exit 0
        ;;
    esac
    ;;
  "pr merge")
    [ -z "${FM_TEST_GH_MERGE_HOOK:-}" ] || "$FM_TEST_GH_MERGE_HOOK"
    exit 0
    ;;
esac
case " $* " in
  *" api repos/"*"/issues/"*"/comments?per_page=100 "*|*" api repos/"*"/pulls/"*"/reviews?per_page=100 "*|*" api repos/"*"/pulls/"*"/comments?per_page=100 "*)
    printf '%s\n' '[[]]'
    ;;
  *" api repos/"*"/commits/"*"/check-runs?filter=all&per_page=100 "*)
    printf '%s\n' '[{"check_runs":[]}]'
    ;;
  *" api repos/"*"/commits/"*"/statuses?per_page=100 "*)
    printf '%s\n' '[[]]'
    ;;
  *" api --paginate repos/"*"/rules/branches/"*merge_queue*)
    ;;
  *" api --paginate repos/"*"/rules/branches/"*)
    printf '%s\n' '[]'
    ;;
  *" api repos/"*"/branches/"*)
    printf '%s\n' '{"name":"main","protected":false}'
    ;;
  *" api repos/"*"/pulls/"*)
    printf '%s\n' "{\"state\":\"open\",\"user\":{\"login\":\"author\"},\"head\":{\"sha\":\"${FM_TEST_GH_HEAD:-0123456789abcdef0123456789abcdef01234567}\"},\"draft\":false,\"mergeable\":true,\"merged_at\":null}"
    ;;
  *" api repos/"*)
    printf '%s\n' '{"permissions":{"push":false}}'
    ;;
  *" headRefOid "*) printf '%s\n' "${FM_TEST_GH_HEAD:-0123456789abcdef0123456789abcdef01234567}" ;;
  *" state "*)
    [ "${FM_TEST_GH_FAIL:-0}" = 0 ] || exit 1
    [ -z "${FM_TEST_GH_STATE_STARTED:-}" ] || : > "$FM_TEST_GH_STATE_STARTED"
    [ "${FM_TEST_GH_SLEEP:-0}" = 0 ] || sleep "$FM_TEST_GH_SLEEP"
    printf '%s\n' "${FM_TEST_GH_STATE:-OPEN}"
    ;;
esac
SH
  cat > "$fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_AXI_LOG"
case "${1:-} ${2:-}" in
  "pr view")
    [ "$#" -eq 5 ] && [ "${4:-}" = --repo ] || exit 2
    printf 'pull_request:\n  number: %s\n  state: %s\n' "$3" "${FM_TEST_GH_MERGE_STATE:-merged}"
    ;;
esac
exit "${FM_TEST_GH_AXI_RC:-0}"
SH
  # Plain glab, reproducing the real CLI's contract: its field output on stdout
  # and exit 0 on success, and a non-zero exit with no stdout on any failure.
  cat > "$fakebin/glab" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GLAB_LOG"
[ "${FM_TEST_GLAB_FAIL:-0}" = 0 ] || exit 1
[ "${FM_TEST_GLAB_SLEEP:-0}" = 0 ] || sleep "$FM_TEST_GLAB_SLEEP"
printf 'title:\tfixture merge request\nstate:\t%s\nauthor:\tsomeone\n' "${FM_TEST_GLAB_STATE:-opened}"
SH
  # gerrit-axi, reproducing the real CLI's contract: one JSON record on stdout
  # and exit 0 on success, and a non-zero exit with no stdout on any failure.
  # Its defaults are the real server's readings for an OPEN change, and the
  # submit fields are settable independently of the status so a case can build
  # the reading a merged change and a merely submittable change share.
  cat > "$fakebin/gerrit-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GERRIT_AXI_LOG"
[ "${FM_TEST_GERRIT_FAIL:-0}" = 0 ] || exit 1
if [ -n "${FM_TEST_GERRIT_RAW:-}" ]; then
  printf '%s\n' "$FM_TEST_GERRIT_RAW"
  exit 0
fi
change=${FM_TEST_GERRIT_CHANGE:-${2:-0}}
printf '{"ok":true,"op":"show","count":1,"missing":[],"changes":[{"change":%s,"subject":%s,"project":"p","status":"%s","wip":false,"submit":"%s","submittable":%s,"blocked_on":"%s","patch_set":1,"revision":"%s","url":"%s"}]}\n' \
  "$change" \
  "${FM_TEST_GERRIT_SUBJECT:-\"fixture change\"}" \
  "${FM_TEST_GERRIT_STATUS:-NEW}" \
  "${FM_TEST_GERRIT_SUBMIT:-NOT_READY}" \
  "${FM_TEST_GERRIT_SUBMITTABLE:-false}" \
  "${FM_TEST_GERRIT_BLOCKED_ON:-Code-Review}" \
  "${FM_TEST_GERRIT_REVISION:-5f07a68436929a527ddc7abadc8ef1abceae40ed}" \
  "${FM_TEST_GERRIT_URL:-https://gerrit.example/c/group/apps/console/+/4201}"
SH
  # no-mistakes, answering only `axi status` the way the real CLI does from a
  # worker copy: a run object, then its branch_sync block. By default the run's
  # result is the copy's own passed HEAD and custody is returned; a case
  # overrides the outcome, the pipeline head, the next action, or makes the read
  # fail.
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
[ -z "${FM_TEST_NM_LOG:-}" ] || printf '%s\n' "$*" >> "$FM_TEST_NM_LOG"
[ "${1:-} ${2:-}" = "axi status" ] || exit 2
[ "${FM_TEST_NM_FAIL:-0}" = 0 ] || exit 1
head=$(git rev-parse HEAD 2>/dev/null) || exit 1
pipeline=${FM_TEST_NM_PIPELINE_HEAD:-$head}
printf 'run:\n  id: "RUNFIXTURE"\n  branch: fm/task\n  status: completed\n  head_sha: %s\noutcome: %s\n' \
  "$pipeline" "${FM_TEST_NM_OUTCOME-passed}"
printf 'branch_sync:\n  state: %s\n  local:\n    head: %s\n  pipeline:\n    current_head: %s\n' \
  "${FM_TEST_NM_SYNC_STATE:-synchronized}" "$head" "$pipeline"
if [ -n "${FM_TEST_NM_NEXT_ACTION:-}" ]; then
  printf '  next_action:\n    code: %s\n    command: no-mistakes axi status\n' "$FM_TEST_NM_NEXT_ACTION"
fi
SH
  chmod +x "$fakebin/gh" "$fakebin/gh-axi" "$fakebin/glab" "$fakebin/gerrit-axi"
  chmod +x "$fakebin/no-mistakes"
  : > "$dir/gh.log"
  : > "$dir/gh-axi.log"
  : > "$dir/glab.log"
  : > "$dir/gerrit-axi.log"
  : > "$dir/guard.log"
  printf '%s\n' "$dir"
}
write_task_meta() {
  local dir=$1 id=${2:-task-a}
  fm_write_meta "$dir/home/state/$id.meta" \
    "window=firstmate:fm-$id" \
    "endpoint_task_id=$id" \
    "worktree=$dir/wt" \
    "project=$dir/project" \
    "kind=ship" \
    "mode=no-mistakes"
}
fm_write_meta() {
  local file=$1 kv
  shift
  : > "$file"
  for kv in "$@"; do
    printf '%s\n' "$kv" >> "$file"
  done
}
