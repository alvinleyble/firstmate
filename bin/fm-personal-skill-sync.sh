#!/usr/bin/env bash
# fm-personal-skill-sync.sh - install or refresh one personal (captain-global)
# skill across every supported harness's own skill-discovery mechanism that is
# actually installed on this machine.
#
# A "personal skill" is a single SKILL.md file with no supporting files,
# fetched from a stable source (an http(s) URL or a local path) and installed
# identically everywhere it applies. This is unrelated to firstmate's own
# project skills under .agents/skills/ (AGENTS.md section 1); this script
# never reads or writes those.
#
# Per-harness mechanism, verified live on this machine and recorded with dated
# evidence in docs/personal-skills.md:
#   - claude:  this script writes ~/.claude/skills/<name>/SKILL.md directly.
#   - codex:   reads ~/.claude/skills natively; no separate write.
#   - pi / pi-signed: reads ~/.claude/skills when ~/.pi/agent/settings.json's
#     "skills" array names it (both identities share that config root); no
#     separate write. This script never edits that captain-owned file.
#   - agy:     reads ~/.claude/skills through the existing
#     ~/.gemini/config/plugins/user-skills-plugin/skills symlink; no separate
#     write. This script never creates or edits agy plugin config.
#   - muse:    has a first-class `muse skills install` command, called
#     directly; it manages its own root (observed at
#     $XDG_CONFIG_HOME/muse/skills) independently of every path below.
#   - grok:    writes ~/.grok/skills/<name>/SKILL.md (grok's own convention;
#     no shared-discovery shortcut exists for it on this fleet).
#   - kimi:    writes ~/.agents/skills/<name>/SKILL.md directly (Kimi Code
#     CLI's own documented global convention; unrelated to muse's root).
#   - opencode: writes ~/.config/opencode/skills/<name>/SKILL.md directly
#     (OpenCode's own documented global convention).
#
# Every action is skipped, not faked, for a harness whose binary is not on
# PATH; each skip is reported by name and reason.
#
# Usage:
#   fm-personal-skill-sync.sh install <name> <source-url-or-path>
#   fm-personal-skill-sync.sh status <name>
#
# `install` is idempotent: re-running it re-reads the source and overwrites
# only this script's own managed files, converging every present and
# supported harness on identical content. It never touches an unrelated file.
set -u

CLAUDE_SKILLS_DIR="${FM_PERSONAL_SKILL_CLAUDE_HOME:-$HOME/.claude}/skills"
AGENTS_SKILLS_DIR="${FM_PERSONAL_SKILL_AGENTS_HOME:-$HOME/.agents}/skills"
GROK_SKILLS_DIR="${FM_PERSONAL_SKILL_GROK_HOME:-$HOME/.grok}/skills"
OPENCODE_SKILLS_DIR="${FM_PERSONAL_SKILL_OPENCODE_HOME:-$HOME/.config/opencode}/skills"
PI_SETTINGS="${FM_PERSONAL_SKILL_PI_HOME:-$HOME/.pi/agent}/settings.json"
AGY_PLUGIN_SKILLS="${FM_PERSONAL_SKILL_AGY_HOME:-$HOME/.gemini/config}/plugins/user-skills-plugin/skills"

usage() { sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'; }

fetch_source() {
  # fetch_source <source-url-or-path> <dest-file> - writes bytes verbatim.
  src=$1
  dest=$2
  case "$src" in
    http://*|https://*)
      curl -fsSL "$src" -o "$dest" ;;
    *)
      [ -f "$src" ] || { echo "error: source file not found: $src" >&2; return 1; }
      cp "$src" "$dest" ;;
  esac
}

write_if_changed() {
  # write_if_changed <dest-file> <content-file>
  dest=$1
  content=$2
  mkdir -p "$(dirname "$dest")" || return 1
  if [ -f "$dest" ] && cmp -s "$dest" "$content"; then
    return 2
  fi
  cp "$content" "$dest.tmp.$$" && mv "$dest.tmp.$$" "$dest"
}

do_install() {
  name=$1
  source=$2
  failed=0
  tmpdir=$(mktemp -d) || { echo "error: could not create a temp directory" >&2; return 1; }
  trap 'rm -rf "$tmpdir"' RETURN
  tmp="$tmpdir/SKILL.md"

  fetch_source "$source" "$tmp" || return 1
  head=$(head -c 3 "$tmp")
  [ "$head" = "---" ] || {
    echo "error: fetched content for '$name' does not look like a SKILL.md (no YAML frontmatter)" >&2
    return 1
  }

  if command -v claude >/dev/null 2>&1; then
    dest="$CLAUDE_SKILLS_DIR/$name/SKILL.md"
    if write_if_changed "$dest" "$tmp"; then
      echo "installed: claude -> $dest"
    else
      rc=$?
      if [ "$rc" -eq 2 ]; then echo "unchanged: claude -> $dest"; else echo "error: could not write $dest" >&2; failed=1; fi
    fi
  else
    echo "skipped: claude (binary not found on PATH)"
  fi

  if command -v codex >/dev/null 2>&1; then
    echo "covered: codex (native ~/.claude/skills discovery; no separate write)"
  else
    echo "skipped: codex (binary not found on PATH)"
  fi

  pi_present=0
  command -v pi >/dev/null 2>&1 && pi_present=1
  command -v pi-signed >/dev/null 2>&1 && pi_present=1
  if [ "$pi_present" -eq 1 ]; then
    if [ -f "$PI_SETTINGS" ] && grep -q '\.claude/skills' "$PI_SETTINGS" 2>/dev/null; then
      echo "covered: pi/pi-signed ($PI_SETTINGS declares ~/.claude/skills; no separate write)"
    else
      echo "warning: pi/pi-signed installed but $PI_SETTINGS does not declare ~/.claude/skills; captain must add it for $name to reach Pi"
    fi
  else
    echo "skipped: pi/pi-signed (binary not found on PATH)"
  fi

  if command -v agy >/dev/null 2>&1; then
    if [ -L "$AGY_PLUGIN_SKILLS" ] && [ "$(cd "$(dirname "$AGY_PLUGIN_SKILLS")" && readlink "$(basename "$AGY_PLUGIN_SKILLS")")" = "$CLAUDE_SKILLS_DIR" ]; then
      echo "covered: agy ($AGY_PLUGIN_SKILLS -> $CLAUDE_SKILLS_DIR; no separate write)"
    else
      echo "warning: agy installed but $AGY_PLUGIN_SKILLS is not the expected symlink to $CLAUDE_SKILLS_DIR; $name may not reach agy"
    fi
  else
    echo "skipped: agy (binary not found on PATH)"
  fi

  if command -v muse >/dev/null 2>&1; then
    if out=$(muse skills install "$tmpdir" --scope user --name "$name" --force --json 2>&1); then
      echo "installed: muse -> user scope ($name)"
    else
      echo "error: muse skills install failed: $out" >&2
      failed=1
    fi
  else
    echo "skipped: muse (binary not found on PATH)"
  fi

  if command -v grok >/dev/null 2>&1; then
    dest="$GROK_SKILLS_DIR/$name/SKILL.md"
    if write_if_changed "$dest" "$tmp"; then
      echo "installed: grok -> $dest"
    else
      rc=$?
      if [ "$rc" -eq 2 ]; then echo "unchanged: grok -> $dest"; else echo "error: could not write $dest" >&2; failed=1; fi
    fi
  else
    echo "skipped: grok (binary not found on PATH)"
  fi

  if command -v kimi >/dev/null 2>&1; then
    dest="$AGENTS_SKILLS_DIR/$name/SKILL.md"
    if write_if_changed "$dest" "$tmp"; then
      echo "installed: kimi -> $dest"
    else
      rc=$?
      if [ "$rc" -eq 2 ]; then echo "unchanged: kimi -> $dest"; else echo "error: could not write $dest" >&2; failed=1; fi
    fi
  else
    echo "skipped: kimi (binary not found on PATH)"
  fi

  if command -v opencode >/dev/null 2>&1; then
    dest="$OPENCODE_SKILLS_DIR/$name/SKILL.md"
    if write_if_changed "$dest" "$tmp"; then
      echo "installed: opencode -> $dest"
    else
      rc=$?
      if [ "$rc" -eq 2 ]; then echo "unchanged: opencode -> $dest"; else echo "error: could not write $dest" >&2; failed=1; fi
    fi
  else
    echo "skipped: opencode (binary not found on PATH)"
  fi

  return "$failed"
}

do_status() {
  name=$1
  [ -f "$CLAUDE_SKILLS_DIR/$name/SKILL.md" ] &&
    echo "present: claude -> $CLAUDE_SKILLS_DIR/$name/SKILL.md" ||
    echo "absent: claude -> $CLAUDE_SKILLS_DIR/$name/SKILL.md"
  [ -f "$GROK_SKILLS_DIR/$name/SKILL.md" ] &&
    echo "present: grok -> $GROK_SKILLS_DIR/$name/SKILL.md" ||
    echo "absent: grok -> $GROK_SKILLS_DIR/$name/SKILL.md"
  [ -f "$AGENTS_SKILLS_DIR/$name/SKILL.md" ] &&
    echo "present: kimi -> $AGENTS_SKILLS_DIR/$name/SKILL.md" ||
    echo "absent: kimi -> $AGENTS_SKILLS_DIR/$name/SKILL.md"
  [ -f "$OPENCODE_SKILLS_DIR/$name/SKILL.md" ] &&
    echo "present: opencode -> $OPENCODE_SKILLS_DIR/$name/SKILL.md" ||
    echo "absent: opencode -> $OPENCODE_SKILLS_DIR/$name/SKILL.md"
  if command -v muse >/dev/null 2>&1; then
    muse skills list --source user --json 2>/dev/null |
      grep -q "\"id\":\"$name\"\|\"id\": \"$name\"" &&
      echo "present: muse (registered in its own skill index)" ||
      echo "absent: muse (not registered in its own skill index)"
  fi
}

case "${1:-}" in
  install)
    [ "$#" -eq 3 ] || { echo "error: install requires <name> <source-url-or-path>" >&2; usage >&2; exit 2; }
    do_install "$2" "$3"
    ;;
  status)
    [ "$#" -eq 2 ] || { echo "error: status requires <name>" >&2; usage >&2; exit 2; }
    do_status "$2"
    ;;
  -h|--help|'') usage ;;
  *) echo "error: unknown command: $1" >&2; usage >&2; exit 2 ;;
esac
