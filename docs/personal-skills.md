# Personal skills across harnesses

A personal skill is a captain-owned SKILL.md the captain can invoke directly in any interactive harness session, independent of any project.
It is unrelated to firstmate's own project skills under `.agents/skills/` (see `AGENTS.md` section 1); this page and its installer never touch those.
`bin/fm-personal-skill-sync.sh` is the single owner of installing and keeping a personal skill consistent across every supported harness on this machine; its header is authoritative for exact mechanics and flags.

## kun

`kun` is Kun Chen's personal `/kun` skill from [kunchenguid/kun](https://github.com/kunchenguid/kun), the only skill published in that repository.
Invoking it loads a near-real-time distillation of Kun Chen's own engineering experience, opinions, voice, and public tools, fetched live from the repo's `ENTRY.md`, `TOOLS.md`, `OPINIONS.md`, and `VOICE.md` on every invocation, so it always reasons from the latest committed knowledge rather than a frozen local copy.
Use it when the captain wants a second, differently-calibrated engineering opinion: reviewing a design or an `AGENTS.md`, thinking through a hard bug, or asking how a seasoned principal engineer would approach a decision.
The skill file itself (`skills/kun/SKILL.md`) is a thin loader with no supporting files; this page intentionally does not restate its content, only how to reach it.

### Invocation per harness

| Harness | Invocation | Status |
|---|---|---|
| Claude Code | `/kun` | Verified live 2026-09-07: discovered from `~/.claude/skills/kun/SKILL.md` immediately after install. |
| Pi / pi-signed | Ask a Kun-flavored question, or try `/kun` | Verified live 2026-09-07 on Pi 0.84.1 via `~/.pi/agent/settings.json`'s `"skills": ["~/.claude/skills"]` entry, which both identities share. No slash-invocation form is separately verified for Pi (see `harness-adapters`), so natural language is the reliable path. |
| agy (Antigravity CLI) | `/kun` | Verified live 2026-09-07 on agy 1.1.10, discovered through the pre-existing `~/.gemini/config/plugins/user-skills-plugin/skills` symlink to `~/.claude/skills`. |
| muse | `/kun` | Verified 2026-09-07 on Muse Code via `muse skills install`'s own `--scope user` root and confirmed with the structural, non-model `muse skills inspect kun --json`. |
| Codex | `$kun` | Installed at the same `~/.claude/skills/kun/SKILL.md` Codex already reads for sibling personal skills (confirmed structurally with `codex debug prompt-input` for existing entries such as `blast-radius`), but a freshly-added entry did not appear in that same structural check within this session despite repeated fresh `codex exec` invocations and clearing Codex's own regenerable caches. This looks like an internal Codex indexing lag with an unknown refresh trigger, not a placement problem. Confirm with `/kun` (or `$kun`) in a normal interactive Codex session; if still absent, wait and retry rather than re-installing. |
| Grok Build | `/kun` | Not installed on this machine, so nothing was written; `grok`'s own global convention (`~/.grok/skills/kun/SKILL.md`) is wired into the sync script and will be populated automatically the next time it runs after Grok is installed. |
| Kimi Code CLI | `/kun` | Not installed on this machine, so nothing was written; Kimi's own documented global convention (`~/.agents/skills/kun/SKILL.md`) is wired into the sync script and will be populated automatically the next time it runs after Kimi is installed. |
| OpenCode | no separate verified skill invocation beyond normal command behavior | Not installed on this machine, so nothing was written; OpenCode's own documented global convention (`~/.config/opencode/skills/kun/SKILL.md`) is wired into the sync script and will be populated automatically the next time it runs after OpenCode is installed. |

### Keeping it current

Re-run the installer any time to refresh every present harness's copy from upstream and to pick up a harness installed since the last run:

```sh
bin/fm-personal-skill-sync.sh install kun https://raw.githubusercontent.com/kunchenguid/kun/main/skills/kun/SKILL.md
bin/fm-personal-skill-sync.sh status kun
```

Both are idempotent: `install` only overwrites a target when its content actually differs, and neither ever touches a harness's own settings, credentials, or unrelated skills.
