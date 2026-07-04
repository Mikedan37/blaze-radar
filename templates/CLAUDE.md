# Agent Awareness (Radar)

Copy this into your repo as `CLAUDE.md` (or equivalent agent playbook).

## Before starting

```bash
blaze radar register "<what you're solving>"
```

## Every 15 minutes or before changing approach

```bash
blaze radar sync
```

## When discovering something

```bash
blaze radar update --found "..."
blaze radar update --ruled-out "hypothesis X is NOT the cause"
```

## Before finishing

```bash
blaze radar done
```

## Rules

- `sync` is your checkpoint — it refreshes git, keeps you alive, and shows **only new findings** since your last sync.
- Look around before duplicating work. Another agent may already be on it.
- Record learnings mid-flight, not only at the end.
