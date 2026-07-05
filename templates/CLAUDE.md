# Radar agent contract (reference)

**Do not copy this file manually.** A production host owns the canonical contract.

In ProjectBlaze:

```bash
blaze radar install
```

That writes a managed block into `CLAUDE.md` at the repo root.

---

## What `install` produces (shape)

```markdown
<!-- BEGIN BLAZE RADAR -->
Radar contract: v2.3
...

# Agent Awareness (Radar)

## Session start

blaze radar sync --task "<what you are working on>"

## Before edits

blaze radar sync

## While working

blaze radar note "what you learned"

## When finished

blaze radar done

Marks your card finished. Off active board. Notes stay in the database.

Cursor hooks sync automatically. Disable: BLAZE_RADAR_HOOKS=0
<!-- END BLAZE RADAR -->
```

---

## Commands (ProjectBlaze host)

| When | Command |
|------|---------|
| Start | `blaze radar sync --task "..."` |
| Read board | `blaze radar sync` |
| Note | `blaze radar note "..."` |
| Change task | `blaze radar sync --task "..."` |
| Done | `blaze radar done` |
| Peek | `blaze radar status` |
| Wire adapters | `blaze radar install` |

---

## Per-repo layout

```
your-repo/CLAUDE.md     → your rules + [managed Radar block]
~/.blaze/radar/workspaces/<repo-hash>/radar.blazedb   → shared board
~/.blaze/radar/workspaces/<repo-hash>/agents/         → per-terminal identity (private)
```

`repo-hash` is derived from `git rev-parse --git-common-dir`, so worktrees share one board.

Re-run `blaze radar install` when the contract version bumps.
