# Live validation: fork merge-passphrase gate after the upstream sync (712591c)

All runs drove the real `bin/fm-pr-merge.sh` / `bin/fm-config-push.sh` from the gate
worktree (mounted read-only at `/fm`) inside a disposable Debian container that shared
the network namespace of a disposable Forgejo 11.0.16 container (tea 0.16.0,
tasks-axi 0.2.6, real tmux 3.5a). FM_HOME, tea config, and the forge were all throwaway
and destroyed after the run. Passphrases are lab placeholders.

| File | What it shows |
| --- | --- |
| `forgejo-passphrase-gate-live.txt` | S1-S3, S5-S9 against real Forgejo PRs: refusal without / with wrong word, merge with the right word, ungated base, live retarget dev->staging gated, wrapup old vs forge-aware command, malformed file, repo line beats `*`, no leak of word or digest. The S4 row in this file hit Forgejo's async mergeability re-check (`mergeable=false`) right after PR #1 moved `staging`; it was re-driven in the next file. |
| `forgejo-passphrase-env-live.txt` | S4 re-driven: wrong / matching `FM_MERGE_PASSPHRASE`, and `--passphrase` winning over a wrong env value. |
| `secondmate-inheritance-live.txt` | P1, P3, P4: `fm-config-push.sh` pushes `config/merge-passphrases` byte-identical, sends no reread for a passphrase-only change, never inlines it (or any sha256 digest) in a mixed reread instruction, and mirrors primary absence. (Its P2 block failed on a fixture-script quoting bug, re-driven below.) |
| `secondmate-merge-gated-live.txt` | P2: a merge run from the secondmate home (FM_HOME=secondmate) into gated `staging` refuses without the word and lands with it. |
| `lab-scripts/` | The exact fixture and driver scripts used. |
