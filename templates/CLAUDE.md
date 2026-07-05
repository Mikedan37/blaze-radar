# Agent Awareness (Radar)

Copy this into your repo as `CLAUDE.md` (or equivalent agent playbook).

Pick a stable agent name for your session (e.g. `claude-a`, `cursor-fix-signup`). Use it on every command.

## Before starting (verify the binary)

Documentation ≠ running capability. In ProjectBlaze:

```bash
source AgentCLI/env.sh
./AgentCLI/scripts/radar-cli-smoke.sh   # must PASS
blaze radar --help                      # must list sync/active — NOT "Needs generation"
```

If smoke fails, rebuild: `cd AgentCLI && swift build -c release`. Do not use Homebrew `blaze` 0.1.x for Radar.

## Session start (required)

```bash
blaze radar sync --agent <your-name>
```

`sync` auto-registers on first use, refreshes git, prints the ACTIVE board, and shows new findings since your last sync.

Optional explicit register:

```bash
blaze radar register "<what you're solving>" --agent <your-name>
```

## Every 15 minutes or before changing approach

```bash
blaze radar sync --agent <your-name>
```

## When discovering something

```bash
blaze radar update --found "..." --agent <your-name>
blaze radar update --ruled-out "hypothesis X is NOT the cause" --agent <your-name>
```

## Before finishing

```bash
blaze radar done --agent <your-name>
```

## Rules

- The **board** is shared (`.blaze/radar/radar.blazedb` in the workspace). Your **identity** and **sync cursor** are private (`~/.blaze/radar/`).
- `sync` is your checkpoint — git refresh, heartbeat, and **only new findings** since your last sync.
- Look around before duplicating work. Another agent may already be on it.
- Record learnings mid-flight, not only at the end.
