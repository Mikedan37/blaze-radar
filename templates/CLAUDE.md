# Radar agent contract (reference)

**Do not copy this file manually.** AgentCLI owns the canonical contract.

In any git repo:

```bash
blaze radar install
```

That writes a managed block into `CLAUDE.md` at the repo root. Your project-specific rules stay outside the markers; Radar injects only the shared behavior.

---

## What `install` produces (shape)

```markdown
<!-- BEGIN BLAZE RADAR -->
Radar contract: v0.3
Installed by AgentCLI: abc1234
Updated: 2026-07-04

# Agent Awareness (Radar)

Use a stable `--agent` name for this session (e.g. `cursor-a`). Same name on every command.

## Before starting (required)

Documentation ≠ running capability. Verify the executable, not just this file:

```bash
blaze radar doctor              # binary, routing, daemon, repo — must pass
blaze radar --help              # must list sync/active — NOT "Needs generation"
```

Session start:

```bash
blaze radar sync --agent <your-name>
```

## During work

Every **15 minutes** or **before changing approach**:

```bash
blaze radar sync --agent <your-name>
```

When discovering something:

```bash
blaze radar update --found "..." --agent <your-name>
blaze radar update --ruled-out "hypothesis is NOT root cause" --agent <your-name>
```

## Before finishing

```bash
blaze radar done --agent <your-name>
```

## Rules

- **Shared:** board + findings live in `.blaze/radar/radar.blazedb` (workspace truth).
- **Private:** your identity + sync cursor live in `~/.blaze/radar/` (per agent).
- `sync` is your checkpoint — git refresh, heartbeat, and **only new findings** since your last sync.
- Look around before duplicating work. Another agent may already be on it.
- Record learnings mid-flight, not only at the end.

Do not edit inside the markers — re-run `blaze radar install` to update.
<!-- END BLAZE RADAR -->
```

---

## Per-repo layout

Each repo keeps its personality; Radar adds only the shared block:

```
SeekerWebsite/CLAUDE.md     → product rules + deploy rules + [managed block]
AgentCore/CLAUDE.md         → backend rules + migration rules + [managed block]
SeekerScore/CLAUDE.md       → matching rules + [managed block]
```

When AgentCLI bumps the contract version, `blaze radar doctor` warns and `blaze radar install` refreshes the block.
