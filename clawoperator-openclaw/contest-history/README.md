# Skill contest history

Results from previous FantaCo demo runs, kept so the judging stays comparable
between events and so a past winner is not re-awarded to a similar idea.

Generate a new one with [`../skill-contest.sh`](../skill-contest.sh), then drop
the report here as `YYYY-MM-DD-<what>.txt` once the winner is announced.

| Date | Clusters | Entries | Winner |
| --- | --- | --- | --- |
| [2026-07-07](2026-07-07-three-clusters.txt) | b2ch2, fbdsr, lqqsv | — | (first scan, superseded two days later) |
| [2026-07-09](2026-07-09-three-clusters.txt) | b2ch2, fbdsr, lqqsv | 63 on b2ch2 alone, 25 users | **user34 (lqqsv) — `customer-wrapped`** |

## The rubric

Carried forward from the July judging and baked into the report `skill-contest.sh`
generates:

1. **CREATIVE** — a concept nobody else attempted
2. **USEFUL** — a real sales-enablement tool, not a toy
3. **DATA-DRIVEN** — uses actual MCP data, not mock or hypothetical
4. **COMPLETE** — thought through past the happy path

`customer-wrapped` won on all four: it borrowed the Spotify Wrapped format and
applied it to real B2B order and project data, producing a year-in-review a rep
could actually send a customer.

## What the July run taught us

- **Themes repeat, and the repeats are not the winners.** Several users
  independently built account-briefing and sales-summary skills. The memorable
  entries were the ones that imported a pattern from outside enterprise software
  — Spotify Wrapped, tarot cards, trading cards, noir detective fiction, deck
  building.
- **Volume is a weak signal, worth keeping as a tiebreak only.** The most
  prolific builder had 7 skills and took an honorable mention, not the win.
  `skill-contest.sh` reports per-user counts for exactly this purpose.
- **Judge from the bodies, not the descriptions.** A one-line description
  flatters whoever writes good copy. Run with `--full` and read
  `contest-skills.md`.
- **Exclude the instructor namespace.** `user1` is staff and seeds examples;
  the script skips it by default.
