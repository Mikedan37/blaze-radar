# Blaze Radar

**A team whiteboard for parallel AI agents.** (v0.3)

When several agents work the same repo at once, they usually cannot see each other. Agent B rediscovers what Agent A already learned. Blaze Radar fixes that: a **shared board** of who is working on what, plus **findings** other agents can read before they duplicate effort.

Think standup, not hive mind. Agents **pull** updates when they sync — nothing is pushed, nothing is assigned, nothing is merged for you.

**Without Radar:**
```
10:00  Agent A discovers the scheduler already exists
11:00  Agent B builds another scheduler
```

**With Radar:**
```
10:00  Agent A records the finding
11:00  Agent B syncs
11:01  Agent B changes approach
```

---

## What it does

| You want to… | Radar gives you… |
|--------------|------------------|
| Say "I'm working on X" | **Registration** on a shared board (branch, task, worktree) |
| Share a discovery mid-flight | **`update --found`** / **`--ruled-out`** (append-only learnings) |
| See what changed since you last looked | **`sync`** — only **new** findings from others, plus full board |
| See everyone active right now | **`active`** |
| Leave the board | **`done`** |
| Get a hint before overlapping work | **Warnings** (file overlap + lightweight topic match — hints, not locks) |

**Success looks like:** Agent B reads Agent A's finding *before* spending hours on the same investigation.

**It does not:** schedule work, claim files, auto-merge, or share one agent identity. Each agent has its own name and sync cursor. Warnings are hints — read the findings; don't expect semantic magic (`auth` vs `session` can still slip through).

---

## Mental model

```
Engineer walks in  →  checks the standup board
Engineer learns    →  writes it on the board
Next engineer      →  reads the board before redoing the work
```

- **Board** (shared between local agents using the same workspace — lives in `<workspace>/.blaze/radar/`, not in git) — global truth for that workspace
- **Your nametag** (private, in `~/.blaze/radar/`) — who you are and what you've already read

Same monorepo, many agents → one board, many private cursors.

---

## Zero setup mode (v0.3)

Most of the time you only need:

```bash
blaze radar doctor                    # preflight (recommended every session)
blaze radar sync --workspace /path/to/repo
```

If you have no identity yet, sync will:

1. Create a generated agent name (e.g. `agent-a3f2`)
2. Register you on the board
3. Save your private cursor under `~/.blaze/radar/`
4. Show the ACTIVE board

Use **`register`** when you want to set an explicit task up front or pick a stable `--agent` name. **`sync`** is the default entry point — including via `blaze run` / `blaze edit` hooks in ProjectBlaze.

First sync captures a baseline: full board visible, nothing marked `+` yet. Later syncs show only **new** findings from others.

---

## Quick start (try it locally)

**Requirements:** macOS 15+, Swift 6+, git

```bash
git clone https://github.com/Mikedan37/blaze-radar.git
cd blaze-radar
swift build -c release
export PATH="$PWD/.build/release:$PATH"

# Terminal 1 — start the demo host (keeps the board database open)
blaze-radar-demo-daemon &

# Terminal 2 — act as an agent (any git repo)
cd /path/to/any/git/repo

blaze-radar-demo radar sync --task "fix prompt scheduler"   # auto-registers if needed
blaze-radar-demo radar update --found "Scheduler already uses cron in Sources/Scheduler"
blaze-radar-demo radar sync
blaze-radar-demo radar active
```

In **ProjectBlaze**, the same commands are `blaze radar …` via AgentCLI + AgentDaemon. Semantics are identical; only the host binary differs.

**ProjectBlaze build (required — source ≠ running binary):**

```bash
cd ProjectBlaze/AgentCLI
swift build -c release
source env.sh
./scripts/radar-cli-smoke.sh    # must PASS — catches stale or unwired binaries
blaze radar --help              # must list sync/active, NOT "Needs generation"
```

Do not use Homebrew `blaze` (0.1.x) for Radar. **Do not copy `templates/CLAUDE.md` by hand** — use distribution:

```bash
cd /path/to/your-repo
blaze radar install      # once per repo — managed block in CLAUDE.md
blaze radar doctor       # every agent session — binary, routing, contract version
blaze radar sync --agent <your-name>
```

See [`templates/CLAUDE.md`](templates/CLAUDE.md) for the **reference shape** of what install writes. AgentCLI owns the canonical contract; install keeps repos aligned when the version bumps.

---

## How to use it (agent workflow)

Pick a **stable name** per session (`agent-a`, `cursor-signup-fix`) if you use `--agent`. Otherwise sync will generate one for you.

### 1. Register (optional — for an explicit task or name)

```bash
blaze radar register "fix signup interruptions" --agent agent-b \
  --workspace /path/to/monorepo \
  --worktree /path/to/your/worktree
```

Skip this if **`sync`** (or a run/edit hook) already auto-registered you. Use register when you want to describe your task before the first sync.

- **`--workspace`** — repo root (where the shared board lives)
- **`--worktree`** — where you're actually editing (defaults to workspace)
- **`--branch`** — optional; detected from git if omitted
- **`--agent`** — your stable name; **re-running register resumes** the same session
- **`--new`** — force a fresh registration (rare)

If you skip `--agent`, a generated name like `agent-a3f2` is created per workspace.

### 2. Sync often (your checkpoint)

```bash
blaze radar sync --agent agent-b
```

Every sync:

1. Refreshes git state for registered worktrees
2. Updates your heartbeat (so others see you're still active)
3. Shows **NEW since last sync** — only findings you haven't seen
4. Prints the full **ACTIVE** board

**When to sync:** every ~15 minutes, before changing approach, before editing a risky area.

Example output shape:

```
SYNC @ 2026-07-05T04:00:00Z
✓ synced findings
✓ git refresh
✓ heartbeat updated

NEW since last sync:
  agent-a (fix/scheduler)
    Found:
      + Scheduler already uses cron — do not duplicate

---

ACTIVE

agent-a
  Branch: fix/scheduler
  Goal:
    fix prompt scheduler
  Learned:
    Scheduler already uses cron — do not duplicate

agent-b
  Branch: fix/signup
  Goal:
    fix signup interruptions
```

On your **first** sync, the full board is shown and nothing is marked `+` — that's your baseline. Later syncs show only new deltas.

### 3. Record learnings as you go

```bash
blaze radar update --found "Found: X is the root cause" --agent agent-b
blaze radar update --ruled-out "NOT a database lock issue" --agent agent-b
blaze radar update --hypothesis "Likely race in checkout flow" --agent agent-b
```

Findings are **append-only**. Other agents see them on their next sync.

### 4. Check the board anytime

```bash
blaze radar active --workspace /path/to/monorepo
```

No delta, no heartbeat — just who's active and what they reported.

### 5. Finish cleanly

```bash
blaze radar done --agent agent-b
```

Marks you done; you drop off the active board. History is preserved.

---

## Two agents, one repo (the scenario this exists for)

```bash
# Agent A — scheduler worktree
blaze radar register "fix prompt scheduler" --agent agent-a --worktree ./wt-scheduler
blaze radar update --found "Found: missing attention arbiter — do NOT build another scheduler" --agent agent-a

# Agent B — signup worktree (different files, related problem space)
blaze radar register "fix signup interruptions" --agent agent-b --worktree ./wt-signup
blaze radar sync --agent agent-b
# → sees A's finding on the board before building overlapping scheduler logic
```

Run `scripts/blaze-radar-sync-e2e.sh` to prove the two-agent delta behavior on the demo stack.

---

## Adoption (ProjectBlaze + multi-repo)

**Once per git repo** — install the coordination contract (no copy-paste drift):

```bash
blaze radar install
```

Writes a version-stamped managed block into `CLAUDE.md`:

```
<!-- BEGIN BLAZE RADAR -->
Radar contract: v0.3
Installed by AgentCLI: abc1234
Updated: 2026-07-04
...
<!-- END BLAZE RADAR -->
```

Project-specific rules stay outside the markers. Re-run `install` when `doctor` reports an outdated contract.

**Every agent session:**

```bash
blaze radar doctor
blaze radar sync --agent <your-name>
```

If you use `blaze run` / `blaze edit`, radar can sync **automatically** at session start. Disable with:

```bash
BLAZE_RADAR_HOOKS=0 blaze run "..."
```

Full distribution docs: `AgentCLI/Docs/Radar.md` in ProjectBlaze.

---

## For framework integrators

This repo ships **`RadarCore`** — the coordination logic. A **host process** (AgentDaemon, or `blaze-radar-demo-daemon`) holds the database connection and forwards requests.

```swift
import RadarCore

let service = AwarenessService()

let reg = try await service.register(
    workspacePath: workspace,
    agentName: "agent-a",
    task: "fix prompt scheduler",
    branch: nil,
    worktree: workspace
)

let result = await service.sync(workspacePath: workspace, registrationId: reg.id)
let board = await service.getActiveWork(workspacePath: workspace, excludeId: nil)
```

Storage is pluggable via `AwarenessStoreProtocol` (production: `BlazeDBAwarenessStore`).

Host wiring (RPC, poller, single-writer rules): [docs/AGENT_DAEMON_INTEGRATION.md](docs/AGENT_DAEMON_INTEGRATION.md).

---

## Where data lives

| What | Where |
|------|--------|
| Shared board | `<workspace>/.blaze/radar/radar.blazedb` |
| Branch summaries | `<workspace>/.blaze/radar/<branch>/summary.md` (derived) |
| Your identity | `~/.blaze/radar/workspaces/{hash}/agents/{id}/session.json` |
| Your sync cursor | `~/.blaze/radar/.../sync.json` |

Add `.blaze/` to `.gitignore`. The shared board is **local runtime state**, not source code — it is not meant to be committed.

Agent identities and sync cursors live **outside the repo** under `~/.blaze/radar/`. Never copy those between agents or machines; each agent owns its own cursor.

---

## Commands reference

| Command | What it does |
|---------|----------------|
| `install` | Install/update managed Radar contract in `CLAUDE.md` (AgentCLI) |
| `doctor` | Preflight: binary, routing, daemon, contract version (AgentCLI) |
| `register "<task>"` | Join or resume on the board |
| `sync` | Heartbeat + git + new deltas + ACTIVE |
| `active` | ACTIVE board only |
| `update --found "…"` | Add a discovery |
| `update --ruled-out "…"` | Record a ruled-out hypothesis |
| `done` | Mark your registration complete |

Common flags: `--workspace`, `--worktree`, `--branch`, `--agent`, `--new` (register only). `doctor --strict` exits non-zero on failure (CI).

---

## Verify

```bash
swift test
scripts/blaze-radar-sync-e2e.sh
```

**ProjectBlaze (AgentCLI):** after `swift build -c release` in `AgentCLI/`:

```bash
./scripts/radar-cli-smoke.sh
```

---

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `BLAZE_RADAR_SOCKET` | `/tmp/blaze_radar.sock` | Demo daemon socket |
| `BLAZE_RADAR_HOOKS` | `1` | ProjectBlaze: `0` disables run/edit hooks |

---

## License

MIT — see [LICENSE](LICENSE).
