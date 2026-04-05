# Plan: Rename openclaw-pairing skill to openclaw-telegram-pairing

## Context
The current `/openclaw-pairing` skill name is ambiguous — it only handles Telegram bot pairing, not gateway Control UI pairing. Renaming clarifies its scope.

## Changes

1. Rename directory `.claude/skills/openclaw-pairing/` → `.claude/skills/openclaw-telegram-pairing/`
2. Update `name:` in SKILL.md frontmatter from `openclaw-pairing` to `openclaw-telegram-pairing`
3. Update usage examples in the SKILL.md body to reference `/openclaw-telegram-pairing`

## Verification
- Confirm the old directory no longer exists
- Confirm the new directory and SKILL.md are correct
