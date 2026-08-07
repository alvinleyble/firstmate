# agy (Antigravity CLI) verification

Active empirical evidence for the `agy` harness adapter.
The behavioral contract lives in the `harness-adapters` skill; this file records the commands and output that currently support it.

Refresh command: `FM_AGY_STOP_LIVE_E2E=1 bin/fm-test-run.sh tests/fm-agy-stop-live-e2e.test.sh`.
Run it after every agy upgrade, because every fact below is agy's rather than firstmate's and a stub cannot prove any of them.
`tests/fm-agy-hooks.test.sh` separately pins the firstmate-owned guard, budget, and installer logic with no agy present.

Verified 2026-08-07 on agy 1.1.10 (`ANTIGRAVITY_LS_VERSION=cli-1.1.10`), account on a Google AI Pro plan.

## Launch profile axes

`--effort` accepts only `low`, `medium`, `high`:

```
$ agy --effort xhigh -p "hi"
Error: invalid model selection (--model "" --effort "xhigh"): invalid --effort "xhigh" (valid: low, medium, high)
$ agy --effort max -p "hi"
Error: invalid model selection (--model "" --effort "max"): invalid --effort "max" (valid: low, medium, high)
```

`--model` and `--effort` are one coupled axis, unlike every other adapter:

```
$ agy --model gemini-3.1-pro-low --effort high -p "reply with just OK"
Error: invalid model selection (--model "gemini-3.1-pro-low" --effort "high"): --model gemini-3.1-pro-low conflicts with --effort=high
$ agy --model gemini-3.1-pro-medium --effort high -p "reply with just OK"
Error: invalid model selection (--model "gemini-3.1-pro-medium" --effort "high"): --effort is not supported for model "gemini-3.1-pro-medium"
```

This is why `effort_flag_for_harness` in `bin/fm-spawn.sh` takes the model and emits no `--effort` for an effort-suffixed model.

## Model selection fails open, twice

An unknown model is not an error; the session silently runs the default `claude-sonnet-4-6`:

```
$ agy --dangerously-skip-permissions --model bogus-model-xyz --prompt-interactive "hi"
(TUI footer) Claude Sonnet 4.6 (Thinking)
```

A model that `agy models` does list can still resolve to a different family, reproducibly across repeated launches:

```
$ agy models
... gemini-3.1-pro-high, gemini-3.1-pro-low, claude-sonnet-4-6, ...
$ agy --dangerously-skip-permissions --model gemini-3.1-pro-high --prompt-interactive "hi"
(TUI footer) Gemini 3.6 Flash · high        # requested 3.1 Pro, got 3.6 Flash
$ agy --dangerously-skip-permissions --model gemini-3.1-pro --effort high --prompt-interactive "hi"
(TUI footer) Gemini 3.6 Flash · high
$ agy --dangerously-skip-permissions --model gemini-3.1-pro-low --prompt-interactive "hi"
(TUI footer) Gemini 3.1 Pro · low           # the only verified route to 3.1 Pro
```

On this version there is no verified way to run Gemini 3.1 Pro above low effort.

## Hook discovery

A workspace `.agents/hooks.json` did not load; the same hook at `~/.gemini/config/hooks.json` fired on the next run.
Both runs used the same git-repo workspace and the same hook script, so discovery location is the only difference.
This is why firstmate installs one global hook rather than a per-worktree hook.

## Stop hook payload and process context

```
--- stop hook invocation 1 cwd=/Users/lovzay/.gemini/config
{"artifactDirectoryPath":"/Users/lovzay/.gemini/antigravity-cli/brain/<conv>","conversationId":"<conv>",
 "error":"","executionNum":0,"fullyIdle":true,"modelName":"claude-sonnet-4-6",
 "terminationReason":"NO_TOOL_CALL",
 "transcriptPath":"/Users/lovzay/.gemini/antigravity-cli/brain/<conv>/.system_generated/logs/transcript_full.jsonl",
 "workspacePaths":[]}
```

Three consequences firstmate depends on:

- The hook's working directory is the directory holding `hooks.json`, not the workspace.
- `workspacePaths` was empty in both print and interactive mode, so the payload cannot identify the task.
- The launch environment IS inherited, which is what supplies the per-task binding instead:

```
$ FM_AGY_TEST=hello-from-launch FM_TASK_ID=harden-agy-harness agy ... -p "Say only PAPAYA."
(hook log) FM_AGY_TEST=[hello-from-launch]  FM_TASK_ID=[harden-agy-harness]
```

## Stop continuation

`{"decision":"continue"}` re-enters the loop and injects `reason` as a system message.
A hook returning `continue` for the first two stops produced two extra model turns that acted on the injected text, then allowed the stop on the third:

```
$ agy --dangerously-skip-permissions -p "Say only the word HELLO and nothing else."
HELLO
BANANA
BANANA
(hook fired 3 times)
```

agy applies no continuation ceiling of its own.
An unconditional `continue` was still looping after 53 invocations when the harness-side timeout ended the run, with `executionNum` incrementing each time.
`state/.agy-autoarm-blocks` in `bin/fm-agy-stop-hook.sh` is therefore the only bound on that loop.

A hook may run far longer than agy's 30s default when `timeout` is set explicitly, which is what makes a bounded foreground watcher checkpoint possible:

```
(hooks.json: "timeout": 90; hook sleeps 45s)
start 1786065988
finished-45s-sleep 1786066033
agy ... 52.167 total
```

## Trust dialog

First launch in a not-yet-trusted directory, not suppressed by `--dangerously-skip-permissions`:

```
Do you trust the contents of this project?
Antigravity CLI requires permission to read, edit, and execute files here.
> Yes, I trust this folder
  No, exit
  ↑/↓ Navigate · enter Confirm
```

One Enter accepts.
A relaunch in the same directory showed no dialog; a fresh directory showed it again.
`~/.gemini/trustedFolders.json` was unchanged across accepted dialogs and clean exits, so it does not predict the dialog.

## TUI facts

Busy footer `esc to cancel` with a braille spinner and `Generating...`; idle footer `? for shortcuts`.
Shortcut pane (`?`) reports `ctrl+d  Exit`, `ctrl+c, esc  Go back / dismiss`, `enter  Send message or confirm`, `/  Open slash commands`.
`/exit` is labelled `Exit the CLI` and exits cleanly:

```
Resume with -c (or command below):
agy --conversation=97a70073-a856-4548-a8a6-9cace4d76635
```

Child/tool processes receive `ANTIGRAVITY_AGENT=1`, `ANTIGRAVITY_CONVERSATION_ID=<uuid>`, and `ANTIGRAVITY_LS_VERSION=cli-1.1.10`; no `CLAUDECODE` or `GROK_AGENT` is set.
