Mode: Antigravity Stop-hook-owned auto-arm

Watcher continuity is owned by a hook, not by you.
The firstmate-owned global Stop hook (`bin/fm-agy-stop-hook.sh`) fires on every stop of this session and runs one bounded watcher checkpoint itself, so supervision continues whether or not you remember anything.
First cycle: drain queued wakes and handle them; the hook starts the first checkpoint when your turn ends.
Ordinary wake: the wake text reaches you as a Stop-hook continuation; drain the durable wake queue, handle the wake, and end your turn.
Do not run `bin/fm-watch-arm.sh` yourself, and never use shell `&`: a second cycle competes with the hook-owned one.
A continuation that says no actionable wake arrived is not work; end that turn immediately so the next checkpoint can start.
Failure or missing cycle only: confirm the hook is installed with `bin/fm-agy-hooks-install.sh status`, and reinstall with `bin/fm-agy-hooks-install.sh install` if it is missing.
If the hook cannot be installed, report that as a blocker rather than substituting a manual arm loop, because a manual loop is exactly the arrangement this adapter replaced.
