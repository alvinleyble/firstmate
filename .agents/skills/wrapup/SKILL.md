---
name: wrapup
description: >-
  Merge a landed PR or approved local-only branch, clean up the task, sweep superseded backlog items, and report a clean outcome when the captain says "wrap up", "merge and wrap up", or invokes /wrapup after testing and confirming a work slice.
user-invocable: true
metadata:
  internal: true
---

# wrapup

Drive the merge, task cleanup, superseded-backlog sweep, and clean-state report when the captain finishes a work slice and says "wrap up", "merge and wrap up", or invokes `/wrapup`.

## 1. Confirm merge authority

1. Check whether the work is already merged or still needs merging.
2. An explicit captain statement to "wrap up" or "merge and wrap up" after testing and confirming a passing slice is itself explicit go-ahead to merge that specific work under `AGENTS.md` hard rule 2 and section 7.
3. Standing `yolo` authority also permits merging green PRs for projects configured with `yolo=on`.
4. Never merge a PR that has failing checks or is not tested and confirmed.
5. When `config/merge-passphrases` gates the PR's base branch, the merge needs the captain's word for that branch in the current request; ask for it rather than guessing or reusing one, and stop if it is not given.

## 2. Land the change

1. If the task's delivery mode is `local-only`, there is no PR: merge the ready branch with `bin/fm-merge-local.sh <task-id>`, then proceed to cleanup.
2. Otherwise, if the PR is already merged or landed on its base branch, proceed directly to cleanup.
3. Otherwise, merge with `bin/fm-pr-merge.sh <task-id> <pr-url> --attended-override -- --delete-branch`; the captain's wrap-up instruction is the explicit instruction that `--attended-override` requires for branch deletion.
   Add the captain's recorded merge method from `data/captain.md` after the `--` (for example `--merge`) when one is recorded, and `--passphrase <word>` before the `--` when the base is gated.
4. If `fm-pr-merge.sh` returns non-zero, check whether the PR was already merged before treating it as an error, and report a refusal rather than working around it.

## 3. Clean up the task

1. Run `bin/fm-teardown.sh <task-id>`; it verifies the work landed, removes the task's isolated copy and records, and refreshes the project's local clone.
2. A refusal for uncommitted or unlanded work is a stop-and-investigate result, never an obstacle to bypass.
3. When the project's own `AGENTS.md` or the captain's recorded wrap ritual names post-landing steps (database migrations, deployments, and the like), dispatch them to a worker; firstmate never runs state-changing commands in a project itself (`AGENTS.md` hard rule 1).

## 4. Sweep superseded backlog items

1. List the other queued and held items in the same backlog as the task just landed (same `FM_HOME` - main or the owning secondmate; never sweep another home's backlog).
2. For any item whose title or body plausibly overlaps what just shipped, check the actual landed diff or current code, not just the title, before concluding it is superseded.
3. Close an ordinary item that check confirms with `tasks-axi done` and a note saying why, and leave genuinely unrelated or still-open items untouched.
4. Never close a captain-held item this way: flag it to the captain as likely superseded with the evidence, and resolve it only through the owner in `captain-hold-lifecycle`.

## 5. Verify and report

1. Verify the project's local clone is clean on its default branch with no leftover task copies.
2. Report in one concise message, translated per `AGENTS.md` section 9: the change is merged (with the full PR URL, or, for a `local-only` task, that there is no PR and the change is merged to local main), cleanup is done, and any post-landing steps were dispatched.
3. Include every backlog item closed or flagged as superseded in that same message rather than folding it into routine cleanup where the captain would never see it.
