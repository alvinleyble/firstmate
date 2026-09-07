#!/usr/bin/env bash
# Behavior tests for the personal-skill cross-harness sync installer.
#
# Every target harness is exercised through PATH stubs and env-overridden
# config-root variables so no real claude/codex/pi/agy/muse/grok/kimi/opencode
# installation is required. This suite pins the logic firstmate owns: which
# harness gets a direct file write, which is reported "covered" with no write,
# idempotency on re-install, and refusal of a malformed source.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SYNC="$ROOT/bin/fm-personal-skill-sync.sh"

TMP=$(fm_test_tmproot fm-personal-skill-sync) || fail "could not create temp root"

fixture="$TMP/KUN_SKILL.md"
cat > "$fixture" <<'EOF'
---
name: kun
description: fixture skill
---

Fixture body.
EOF

# --- scenario A: no harness binaries on PATH --------------------------------

homeA="$TMP/homeA"
mkdir -p "$homeA"
outA=$(PATH="/usr/bin:/bin" \
  FM_PERSONAL_SKILL_CLAUDE_HOME="$homeA/claude" \
  FM_PERSONAL_SKILL_AGENTS_HOME="$homeA/agents" \
  FM_PERSONAL_SKILL_GROK_HOME="$homeA/grok" \
  FM_PERSONAL_SKILL_PI_HOME="$homeA/pi" \
  FM_PERSONAL_SKILL_AGY_HOME="$homeA/gemini/config" \
  FM_PERSONAL_SKILL_OPENCODE_HOME="$homeA/opencode" \
  "$SYNC" install kun "$fixture" 2>&1) || fail "install with no binaries present should still exit 0, got: $outA"

for h in claude codex "pi/pi-signed" agy muse grok kimi opencode; do
  printf '%s\n' "$outA" | grep -q "skipped: $h" ||
    fail "expected '$h' to be reported skipped with no binaries on PATH: $outA"
done
[ -e "$homeA/claude/skills/kun/SKILL.md" ] && fail "no file should be written when claude is not present"
pass "every harness is reported skipped, and nothing is written, when no binaries are on PATH"

# --- scenario B: only claude present, then a second idempotent run ---------

fakebin=$(fm_fakebin "$TMP")
fm_fake_exit0 "$fakebin" claude

homeB="$TMP/homeB"
mkdir -p "$homeB"
run_b() {
  PATH="$fakebin:/usr/bin:/bin" \
    FM_PERSONAL_SKILL_CLAUDE_HOME="$homeB/claude" \
    FM_PERSONAL_SKILL_AGENTS_HOME="$homeB/agents" \
    FM_PERSONAL_SKILL_GROK_HOME="$homeB/grok" \
    FM_PERSONAL_SKILL_PI_HOME="$homeB/pi" \
    FM_PERSONAL_SKILL_AGY_HOME="$homeB/gemini/config" \
    FM_PERSONAL_SKILL_OPENCODE_HOME="$homeB/opencode" \
    "$SYNC" install kun "$fixture" 2>&1
}

out1=$(run_b) || fail "first install should succeed: $out1"
printf '%s\n' "$out1" | grep -q "^installed: claude ->" || fail "first run should report a fresh claude install: $out1"
cmp -s "$homeB/claude/skills/kun/SKILL.md" "$fixture" || fail "installed content must be byte-identical to the source"

out2=$(run_b) || fail "second install should succeed: $out2"
printf '%s\n' "$out2" | grep -q "^unchanged: claude ->" || fail "re-running with identical content should report unchanged, got: $out2"
pass "claude gets a direct byte-identical write, and re-install is idempotent"

# --- scenario C: every harness present and correctly wired ------------------

fm_fake_exit0 "$fakebin" claude codex pi agy grok kimi opencode
museargs="$TMP/muse-args.log"
cat > "$fakebin/muse" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$museargs"
exit 0
EOF
chmod +x "$fakebin/muse"

homeC="$TMP/homeC"
mkdir -p "$homeC/pi"
printf '{"skills": ["~/.claude/skills"]}\n' > "$homeC/pi/settings.json"
mkdir -p "$homeC/claude/skills" "$homeC/gemini/config/plugins/user-skills-plugin"
ln -s "$homeC/claude/skills" "$homeC/gemini/config/plugins/user-skills-plugin/skills"

outC=$(PATH="$fakebin:/usr/bin:/bin" \
  FM_PERSONAL_SKILL_CLAUDE_HOME="$homeC/claude" \
  FM_PERSONAL_SKILL_AGENTS_HOME="$homeC/agents" \
  FM_PERSONAL_SKILL_GROK_HOME="$homeC/grok" \
  FM_PERSONAL_SKILL_PI_HOME="$homeC/pi" \
  FM_PERSONAL_SKILL_AGY_HOME="$homeC/gemini/config" \
  FM_PERSONAL_SKILL_OPENCODE_HOME="$homeC/opencode" \
  "$SYNC" install kun "$fixture" 2>&1) || fail "install with every harness present should succeed: $outC"

printf '%s\n' "$outC" | grep -q "^installed: claude ->" || fail "claude should get a direct write: $outC"
printf '%s\n' "$outC" | grep -q "^covered: codex" || fail "codex should be reported covered: $outC"
printf '%s\n' "$outC" | grep -q "^covered: pi/pi-signed" || fail "pi should be reported covered when settings.json declares the path: $outC"
printf '%s\n' "$outC" | grep -q "^covered: agy" || fail "agy should be reported covered when the plugin symlink is correct: $outC"
printf '%s\n' "$outC" | grep -q "^installed: muse ->" || fail "muse should be reported installed: $outC"
printf '%s\n' "$outC" | grep -q "^installed: grok ->" || fail "grok should get a direct write: $outC"
printf '%s\n' "$outC" | grep -q "^installed: kimi ->" || fail "kimi should get a direct write: $outC"
printf '%s\n' "$outC" | grep -q "^installed: opencode ->" || fail "opencode should get a direct write: $outC"

cmp -s "$homeC/grok/skills/kun/SKILL.md" "$fixture" || fail "grok's copy must be byte-identical to the source"
cmp -s "$homeC/agents/skills/kun/SKILL.md" "$fixture" || fail "kimi's copy must be byte-identical to the source"
cmp -s "$homeC/opencode/skills/kun/SKILL.md" "$fixture" || fail "opencode's copy must be byte-identical to the source"
grep -q -- "--scope user" "$museargs" || fail "muse must be invoked with --scope user"
grep -q -- "--name kun" "$museargs" || fail "muse must be invoked with --name kun"
grep -q -- "--force" "$museargs" || fail "muse must be invoked with --force so re-installs converge"
pass "every present and correctly wired harness is installed or reported covered, with no unrelated writes"

# --- scenario D: agy present but the plugin symlink is wrong ----------------

homeD="$TMP/homeD"
mkdir -p "$homeD/gemini/config/plugins/user-skills-plugin" "$homeD/claude/skills" "$homeD/elsewhere"
ln -s "$homeD/elsewhere" "$homeD/gemini/config/plugins/user-skills-plugin/skills"

outD=$(PATH="$fakebin:/usr/bin:/bin" \
  FM_PERSONAL_SKILL_CLAUDE_HOME="$homeD/claude" \
  FM_PERSONAL_SKILL_AGENTS_HOME="$homeD/agents" \
  FM_PERSONAL_SKILL_GROK_HOME="$homeD/grok" \
  FM_PERSONAL_SKILL_PI_HOME="$homeD/pi" \
  FM_PERSONAL_SKILL_AGY_HOME="$homeD/gemini/config" \
  FM_PERSONAL_SKILL_OPENCODE_HOME="$homeD/opencode" \
  "$SYNC" install kun "$fixture" 2>&1)

printf '%s\n' "$outD" | grep -q "^warning: agy installed but" ||
  fail "a wrong agy plugin symlink target must be reported as a warning, not silently claimed covered: $outD"
pass "agy is never falsely claimed covered when its plugin symlink does not point at the claude skills dir"

# --- scenario E: pi present but settings.json is missing the declaration ---

homeE="$TMP/homeE"
mkdir -p "$homeE/pi" "$homeE/claude/skills"
printf '{"skills": []}\n' > "$homeE/pi/settings.json"

outE=$(PATH="$fakebin:/usr/bin:/bin" \
  FM_PERSONAL_SKILL_CLAUDE_HOME="$homeE/claude" \
  FM_PERSONAL_SKILL_AGENTS_HOME="$homeE/agents" \
  FM_PERSONAL_SKILL_GROK_HOME="$homeE/grok" \
  FM_PERSONAL_SKILL_PI_HOME="$homeE/pi" \
  FM_PERSONAL_SKILL_AGY_HOME="$homeE/gemini/config" \
  FM_PERSONAL_SKILL_OPENCODE_HOME="$homeE/opencode" \
  "$SYNC" install kun "$fixture" 2>&1)

printf '%s\n' "$outE" | grep -q "^warning: pi/pi-signed installed but" ||
  fail "pi installed without the settings.json declaration must be reported as a warning, not silently claimed covered: $outE"
pass "pi is never falsely claimed covered when its settings.json does not declare the claude skills path"

# --- scenario F: malformed source is refused before any write --------------

badsource="$TMP/bad.md"
printf 'not a skill file\n' > "$badsource"
homeF="$TMP/homeF"
mkdir -p "$homeF"

if outF=$(PATH="$fakebin:/usr/bin:/bin" \
  FM_PERSONAL_SKILL_CLAUDE_HOME="$homeF/claude" \
  FM_PERSONAL_SKILL_AGENTS_HOME="$homeF/agents" \
  FM_PERSONAL_SKILL_GROK_HOME="$homeF/grok" \
  FM_PERSONAL_SKILL_PI_HOME="$homeF/pi" \
  FM_PERSONAL_SKILL_AGY_HOME="$homeF/gemini/config" \
  FM_PERSONAL_SKILL_OPENCODE_HOME="$homeF/opencode" \
  "$SYNC" install kun "$badsource" 2>&1); then
  fail "a source with no YAML frontmatter must be refused, got success: $outF"
fi
[ -e "$homeF/claude/skills/kun/SKILL.md" ] && fail "a refused source must not write anything to claude's directory"
pass "a malformed source is refused before any harness is touched"

# --- status subcommand ------------------------------------------------------

outStatus=$(PATH="$fakebin:/usr/bin:/bin" \
  FM_PERSONAL_SKILL_CLAUDE_HOME="$homeC/claude" \
  FM_PERSONAL_SKILL_AGENTS_HOME="$homeC/agents" \
  FM_PERSONAL_SKILL_GROK_HOME="$homeC/grok" \
  FM_PERSONAL_SKILL_PI_HOME="$homeC/pi" \
  FM_PERSONAL_SKILL_AGY_HOME="$homeC/gemini/config" \
  FM_PERSONAL_SKILL_OPENCODE_HOME="$homeC/opencode" \
  "$SYNC" status kun 2>&1) || fail "status should succeed: $outStatus"
printf '%s\n' "$outStatus" | grep -q "^present: claude ->" || fail "status should report claude present after install: $outStatus"
printf '%s\n' "$outStatus" | grep -q "^present: grok ->" || fail "status should report grok present after install: $outStatus"
printf '%s\n' "$outStatus" | grep -q "^present: kimi ->" || fail "status should report kimi present after install: $outStatus"
printf '%s\n' "$outStatus" | grep -q "^present: opencode ->" || fail "status should report opencode present after install: $outStatus"
pass "status reports the on-disk presence of every direct-write target"
