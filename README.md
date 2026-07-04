# Blaze Radar

**A BlazeDB-backed coordination layer for parallel AI coding agents.**

When you run multiple Claude/Cursor agents across git worktrees, nobody knows what anyone else is doing. Blaze Radar is the team whiteboard — not a project manager, not a merge bot, not Skynet. Just observability so agents stop duplicating each other's investigations.

```
Engineer walks in  → checks the standup board
Engineer learns    → updates the board
Next engineer      → avoids redoing the same discovery
```

> **Fully usable from this repo.** You do **not** need AgentDaemon, ProjectBlaze, or any private Blaze infrastructure to clone, build, and run Blaze Radar. This repository ships its own daemon (`blaze-radar-daemon`) and CLI (`blaze`).

---

## What this is not

Blaze Radar does **not** make agents share a brain. It gives them the same situational awareness human engineers get from standups, PRs, and Slack.

People will misunderstand this. Blaze Radar is:

| It is | It is not |
|-------|-----------|
| A team whiteboard | A project manager |
| Situational awareness | A shared mind / hive consciousness |
| Pull-based observation | Push notifications or autopilot |
| "Look around before duplicating work" | Scheduling, assignment, or ownership claims |
| Awareness first | A merge train (that comes later, if the pain earns it) |

**The actual product metric:** Did Agent B learn what Agent A discovered *before* spending three hours on the same investigation?

The scheduler collision that motivated this wasn't a code-generation failure. Both agents wrote good code. The failure was that they didn't know they were coworkers. That's the bug Blaze Radar patches.

**Adoption reality:** Radar only works if agents actually use it. `blaze radar sync` needs to become muscle memory — every 15 minutes or before changing approach. If agents ignore it, you get that one Confluence page nobody has updated since 2019, but in Markdown.

**Longer term (not v1):** MCP integration could lower the "remember to run a shell command" problem — auto-register on session start, a tool call to check radar, auto-update on discoveries. Not because MCP is magically smarter, but because it removes friction. For now: awareness first, merge train second.

---

## The problem

Running 4–6 agents in parallel on one monorepo fails in predictable ways:

| Failure | What happens |
|---------|--------------|
| **Duplicate discovery** | Agent B spends 3 hours rediscovering what Agent A already found |
| **Concept collisions** | Same underlying system, different files — file-level locks don't help |
| **Tunnel vision** | Agent checks radar at T+0, pivots at T+30, never looks again |
| **Integration blindness** | Nobody knows what's landing on `main` (out of scope for v1) |

The human was the only shared memory. That doesn't scale.

---

## What Blaze Radar fixes

**Core invariant:** If Agent A learns something important, Agent B can discover it *before* duplicating the work.

Blaze Radar gives you:

- **Registration** — agents declare what they're solving and which worktree they're in
- **Living branch summaries** — mid-investigation learnings via `update`, not just at the end
- **Related-area warnings** — dumb-but-effective token overlap detects conceptual collisions
- **Git observation** — daemon independently polls registered worktrees (trust, but verify)
- **Sync checkpoints** — one command refreshes heartbeat, git state, and shows *only new findings* since your last sync

Fix "nobody knows what anyone is doing" first. Let the next pain earn its right to exist. See [What this is not](#what-this-is-not) for scope boundaries.

---

## What's public vs. private

Blaze Radar was extracted from an internal agent stack. Here's what you can and cannot access today:

| Component | Status | Notes |
|-----------|--------|-------|
| **blaze-radar** (this repo) | **Public** | Clone, build, run, contribute — complete standalone tool |
| **[BlazeDB](https://github.com/Mikedan37/BlazeDB)** | **Public** | Embedded persistence engine; SwiftPM dependency |
| **AgentDaemon** | **Private** | Internal agent runtime — **not required** to use Blaze Radar |
| **ProjectBlaze** | **Private** | Parent monorepo — **not required**; no public repo |
| **AgentCLI / full Blaze agent tooling** | **Private** | Broader CLI beyond `blaze radar` — not in this repo |

**What this means for you:**

- You **can** run multi-agent awareness today with only this repo + BlazeDB.
- You **cannot** drop this into the private AgentDaemon wire protocol or get the full ProjectBlaze agent runtime from GitHub.
- If you work inside the private Blaze stack, Radar's awareness model maps to the internal design — but this open repo is the reference implementation.

> **Why this repo exists publicly**  
> The proprietary agent runtime stays private due to IP. Blaze Radar is the **showable architecture** — a real coordination layer powered by BlazeDB, demonstrating how parallel coding agents share situational awareness without exposing internal agent code.

---

## Architecture

```mermaid
flowchart TB
    subgraph agents["Parallel agents (Claude / Cursor / CLI)"]
        A1["Agent A\nworktree: fix/scheduler"]
        A2["Agent B\nworktree: fix/signup"]
        A3["Agent N…"]
    end

    subgraph cli["blaze CLI"]
        REG["radar register"]
        SYNC["radar sync"]
        UPD["radar update"]
        ACT["radar active"]
        DONE["radar done"]
    end

    subgraph daemon["blaze-radar-daemon"]
        RPC["JSON-RPC handler\n/tmp/blaze_radar.sock"]
        SVC["AwarenessService"]
        POLL["Git poller\n30s interval"]
        DET["RelatedAreaDetector\ntoken overlap + signals"]
        REGISTRY["WorkspaceRegistry\nregistered workspace roots"]
    end

    subgraph git["Registered worktrees"]
        WT1["git worktree A"]
        WT2["git worktree B"]
    end

    subgraph store["AwarenessStore (pluggable)"]
        API["AwarenessStoreProtocol"]
        BDB["BlazeDBAwarenessStore\n(default)"]
        JSON["JSONAwarenessStore\n(optional adapter)"]
    end

    subgraph blazedb["BlazeDB — single-writer coordination"]
        DB[".blaze/radar.blazedb"]
        AGENTS["agents"]
        FINDINGS["findings / events"]
        GITOBS["git_observations"]
        SYNCDB["sync_state"]
    end

    A1 & A2 & A3 --> REG & SYNC & UPD & ACT & DONE
    REG & SYNC & UPD & ACT & DONE --> RPC
    RPC --> SVC
    SVC --> API
    API --> BDB
    API -.-> JSON
    BDB --> DB
    DB --> AGENTS & FINDINGS & GITOBS & SYNCDB
    SVC --> SUMMARY[".blaze/radar/&lt;branch&gt;/summary.md"]
    SYNC -.-> SYNCFILE[".blaze/radar-sync.json\n(client delta baseline)"]
    REG & SYNC -.-> SESSION[".blaze/radar-session.json"]
    SVC --> REGISTRY
    REGISTRY --> WSINDEX["~/.blaze/daemon/radar-workspaces.json"]
    POLL --> REGISTRY
    SVC --> DET
    POLL --> WT1 & WT2
    WT1 & WT2 -.->|"branch, HEAD, changed files"| SVC
    DET -.->|"related areas, file overlaps"| RPC
    RPC -.->|"ACTIVE board + NEW deltas"| A1 & A2 & A3
```

### Data flow (one `sync`)

```mermaid
sequenceDiagram
    participant Agent as Agent CLI
    participant Daemon as blaze-radar-daemon
    participant Store as BlazeDB (.blaze/radar.blazedb)
    participant Git as git worktrees
    participant Sync as radar-sync.json

    Agent->>Daemon: sync(workspace, registrationId)
    Daemon->>Git: poll registered worktrees
    Git-->>Daemon: branch, HEAD, changed files
    Daemon->>Store: upsert agent + append findings + git observations
    Daemon->>Store: record sync_state event
    Daemon->>Daemon: RelatedAreaDetector
    Daemon-->>Agent: ActiveWorkSnapshot
    Agent->>Sync: load previous baseline
    Agent->>Agent: diff → show only NEW findings
    Agent->>Sync: save new baseline
    Agent->>Agent: print ACTIVE board
```

| Module | Role |
|--------|------|
| `RadarCore` | `AwarenessStoreProtocol`, BlazeDB store, awareness service, git observer, related-area detector |
| `RadarDaemon` | Background daemon + git poller |
| `RadarClient` | Unix socket client |
| `BlazeCLI` | `blaze radar` commands |

The daemon tracks registered workspace roots in `~/.blaze/daemon/radar-workspaces.json` and polls **only those worktrees** — no hardcoded repo paths.

### Storage: BlazeDB-backed coordination

Blaze Radar uses **[BlazeDB](https://github.com/Mikedan37/BlazeDB)** as the embedded persistence engine — not a shared Markdown file.

```
Claude Code agents
        ↓
    Blaze Radar
        ↓
     BlazeDB
        ↓
single-writer serialized state
durable events
agent coordination log
```

**Why BlazeDB:** Multiple agents writing simultaneously must never corrupt state. BlazeDB provides single-writer coordination, durable append-style findings, and queryable history. This is structured coordination — not `echo >> standup.md`.

**Pluggable storage:** `AwarenessStoreProtocol` defines the API. `BlazeDBAwarenessStore` is the default. `JSONAwarenessStore` remains as an optional adapter for lightweight testing — not the production architecture.

| Collection | Purpose |
|------------|---------|
| `RadarAgent` | Registration core fields (task, branch, status, lastSeen) |
| `RadarFinding` | Append-only discoveries, ruled-out hypotheses, invariants |
| `RadarGitObservation` | Git poll history per agent |
| `RadarSyncState` | Sync checkpoint events |

Database path: `<workspace>/.blaze/radar.blazedb`

---

## Quick start

**Requirements:** macOS 15+, Swift 6+, git

```bash
git clone https://github.com/Mikedan37/blaze-radar.git
cd blaze-radar
swift build -c release
```

### 1. Start the daemon

```bash
.build/release/blaze-radar-daemon &
# listens on /tmp/blaze_radar.sock
```

### 2. Agent playbook

Copy `templates/CLAUDE.md` into your repo root (or add to your agent instructions):

```bash
# Before starting
blaze radar register "fix prompt scheduler"

# Every 15 minutes or before changing approach
blaze radar sync

# When you learn something
blaze radar update --found "missing attention arbiter — don't build another scheduler"

# When done
blaze radar done
```

### 3. Install the CLI (optional)

```bash
cp .build/release/blaze /usr/local/bin/blaze
# or symlink wherever your PATH looks
```

---

## Commands

| Command | Purpose |
|---------|---------|
| `blaze radar register "<task>"` | Declare what you're working on |
| `blaze radar sync` | Heartbeat + git refresh + delta findings + full board |
| `blaze radar active` | Show all active work (no delta) |
| `blaze radar update --found "..."` | Record mid-flight learnings |
| `blaze radar update --ruled-out "..."` | Record ruled-out hypotheses |
| `blaze radar done` | Mark your registration complete |

### Flags

```bash
blaze radar register "fix signup flow" \
  --workspace /path/to/monorepo \
  --worktree /path/to/worktree \
  --branch fix/signup \
  --agent claude-session-3
```

---

## How it works

### Persistence

Coordination state lives in BlazeDB inside your repo. CLI session files are local to each agent process:

```
your-repo/
  .blaze/
    radar.blazedb              # BlazeDB — agents, findings, git obs, sync history
    radar-session.json         # this CLI session's registration id
    radar-sync.json            # client-side delta baseline for sync output
    radar/<branch>/summary.md  # human-readable branch notes (derived)
```

### Sync semantics

1. **First sync** — captures baseline. Full ACTIVE board shown; nothing marked as NEW.
2. **Later syncs** — compares against `.blaze/radar-sync.json`, shows only `+` prefixed deltas from other agents.
3. **Heartbeat** — bumps your `lastSeen` so the 30-minute stale reaper doesn't withdraw you mid-session.

### Related-area detection

No embeddings. Token intersection + domain signal words (`signup`, `attention`, `scheduler`, etc.) + file/path overlap. Intentionally dumb — fast, debuggable, good enough.

---

## Example: the test that matters

This is the scenario Blaze Radar was built for — not unit tests, but the *"two agents independently approach the same conceptual area"* test:

```bash
# Agent A (fix/prompt-scheduler worktree)
blaze radar register "fix prompt scheduler"
blaze radar update --found "Found: missing attention arbiter, don't build another scheduler"

# Agent B (fix/signup-interruptions worktree)  
blaze radar register "fix signup interruptions"
blaze radar sync    # sees A's finding on the board

# Agent B avoids building a second scheduler. Humanity survives another Tuesday.
```

### Sync delta proof

```bash
scripts/blaze-radar-sync-e2e.sh
```

This script proves:

1. Agent B's **baseline sync** sees Agent A's first finding in ACTIVE (not as a `+` delta)
2. After Agent A posts a **second** finding, Agent B's sync shows **only** the new one

```
PASS: baseline captured
PASS: finding one in ACTIVE
PASS: finding one not in NEW delta
PASS: only finding two is new
PASS: finding one not repeated
```

Unit tests (`swift test`) cover persistence, related-area detection, sync heartbeat, and **10-agent concurrent register/update/sync** (no lost findings, no corruption).

---

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `BLAZE_RADAR_SOCKET` | `/tmp/blaze_radar.sock` | Daemon socket path |

---

## Relationship to the private Blaze stack

Blaze Radar originated as the awareness layer inside a **private** ProjectBlaze / AgentDaemon codebase. That parent project is not on GitHub. **This repo is the open, self-contained version.**

| | Private Blaze stack | Blaze Radar (this repo) |
|--|---------------------|-------------------------|
| Availability | Internal only | Public on GitHub |
| Persistence | BlazeDB via AgentDaemon | BlazeDB via `BlazeDBAwarenessStore` |
| Wire protocol | BlazeBinary over AgentDaemon | JSON over Unix socket |
| Socket | `/tmp/blaze_agent.sock` | `/tmp/blaze_radar.sock` |
| Daemon | AgentDaemon (private) | `blaze-radar-daemon` (included here) |
| Scope | Full agent runtime | Awareness layer only |
| Mental model | register, sync, update, done | Same |

You do not need access to the private stack to use or contribute to this project. If you have both environments, they can run side by side during migration.

---

## Contributing

Contributions welcome on awareness, storage adapters, CLI ergonomics, tests, and docs.

```bash
git clone https://github.com/Mikedan37/blaze-radar.git
cd blaze-radar
swift build
swift test
scripts/blaze-radar-sync-e2e.sh   # e2e proof
```

**Good first areas:** `RelatedAreaDetector` signal words, `AwarenessStoreProtocol` adapters, MCP tooling (out of scope for core v1 but welcome as experiments), README and playbook improvements.

Please keep PRs focused on **awareness only** — no scheduling, assignment, merge automation, or agent control. Open an issue before large architectural changes.

---

## License

MIT — see [LICENSE](LICENSE).
