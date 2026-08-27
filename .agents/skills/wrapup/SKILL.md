---
name: wrapup
description: >-
  Merge a landed PR, run post-landing project cleanup, sweep stale branches, worktrees, and superseded backlog items, and report a clean outcome when the captain says "wrap up", "merge and wrap up", or invokes /wrapup after testing and confirming a work slice.
user-invocable: true
metadata:
  internal: true
---

# wrapup

Drive the post-landing merge, project cleanup, repo and backlog staleness sweep, and clean state verification when the captain finishes a work slice and says "wrap up", "merge and wrap up", or invokes `/wrapup`.

## 1. Confirm merge authority

1. Check whether the work is already merged or requires merging.
2. An explicit captain statement to "wrap up" or "merge and wrap up" after testing and confirming a passing slice is itself explicit go-ahead to merge that specific work under `AGENTS.md` hard rule 2 and section 7.
3. Standing `yolo` authority also permits merging green PRs for projects configured with `yolo=on`.
4. Never merge a PR that has failing checks or is not tested and confirmed.

## 2. Land the change

1. If the PR is already merged on GitHub or landed on the default branch, proceed directly to cleanup.
2. Otherwise, merge the PR using `bin/fm-pr-merge.sh <task-id> <pr-url> -- --merge --delete-branch`.
3. If `fm-pr-merge.sh` returns non-zero, verify whether the PR was already merged before treating it as an error.

## 3. Post-landing cleanup and repo staleness sweep

1. Run `bin/fm-teardown.sh <task-id>` to execute post-landing cleanup and the repo-wide staleness sweep for the task's project.
2. `fm-teardown.sh` verifies that work is landed, tears down the task worktree, checks documentation progress, checks and applies pending Supabase database migrations, deploys changed Supabase Edge Functions, syncs the primary clone with the default branch, prunes remote tracking branches, and sweeps the project repository for provably landed local and remote task branches and prunable worktree registrations (`docs/architecture.md` owns the exact deletion rules).
3. If teardown reports an uncommitted changes or unlanded work refusal, stop and investigate immediately rather than bypassing safety checks.

## 4. Sweep superseded backlog items

1. List the other queued and held items in the same backlog as the task just landed (same `FM_HOME` - main or the owning secondmate; never sweep another home's backlog).
2. For any item whose title or body plausibly overlaps what was just shipped - grill items and `kind: captain` decision-hold items are the common case, since they are the ones most likely to go stale silently without anyone closing them (`decision-hold-lifecycle` owns the hold lifecycle contract) - check the actual landed diff or current code, not just the title, before concluding it is superseded.
3. Close (`tasks-axi done`, with a note explaining why) or explicitly flag as superseded any item that check confirms, while leaving genuinely unrelated or still-open items untouched.
4. Report what was closed or flagged as part of the wrapup outcome message to the captain, translated per `AGENTS.md` section 9's plain-language rules, and do not silently fold this into the routine-cleanup summary where the captain would never see it.

## 5. Verify and report clean state

1. Verify that the project checkout is clean on the default branch with no dangling task worktrees or leftover merged feature branches.
2. Report the outcome to the captain using the outcome language required by `AGENTS.md` section 9.
3. Translate internal mechanics into plain captain-facing outcomes: do not mention worktrees, task IDs, teardown scripts, metadata files, or status records.
4. Confirm in one concise message that the change is merged, database migrations and edge functions are up to date (when applicable), the local repository is synced, and temporary resources are cleaned up.
5. If any backlog items were closed or flagged as superseded in step 4, include them clearly in that outcome message.
