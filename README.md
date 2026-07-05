# Blaze Radar

**Claude and Cursor sessions don't know each other exist. Radar puts a local board in the repo. Every agent checks the board before work and leaves notes.**

A whiteboard. Not a project manager. Not Jira for bots.

**The bet:** dumb coordination layer → smart workers with context.

---

## What you're getting

This repo ships three things:

| Piece | What it is |
|-------|------------|
| **RadarCore** | The engine — shared board state in BlazeDB |
| **Demo host** | `blaze-radar-demo` — try it today, no other deps |
| **Pattern** | How a host makes agents look at the board before work |

There is no universal `radar` binary. Your host chooses the prefix:

```
your-tool radar sync
your-tool radar note "..."
```

Radar works in **any git repo**. The board lives at the **repository root** — not on a branch:

```
MyApp/
  .git/
  .blaze/
    radar/
      radar.blazedb
```

All agents working in that repo share one board, no matter which branch they're on.

---

## Try Radar today

This repo includes a demo host.

```bash
git clone https://github.com/Mikedan37/blaze-radar.git
cd blaze-radar
swift build -c release
export PATH="$PWD/.build/release:$PATH"
blaze-radar-demo-daemon &
```

Then in **any git repo**:

```bash
cd ~/SomeRandomRepo

blaze-radar-demo radar sync --task "auth bug"
blaze-radar-demo radar note "DB is not the issue"

# second terminal, same repo
blaze-radar-demo radar sync
```

```bash
swift test
```

---

## Commands

Same subcommands on any host. The demo uses `blaze-radar-demo radar …`.

| When | Command |
|------|---------|
| Start / read board | `blaze-radar-demo radar sync` |
| Say what you're on | `blaze-radar-demo radar sync --task "auth bug"` |
| Learned something | `blaze-radar-demo radar note "..."` |
| Changed focus | `blaze-radar-demo radar sync --task "new task"` |
| Finished | `blaze-radar-demo radar done` |
| Peek (no heartbeat) | `blaze-radar-demo radar status` |

`install` (Claude contract, Cursor hooks) is a **host feature** — the demo does not include it. See [ProjectBlaze](#projectblaze-reference-host) for how a production host wires that up.

---

## Add Radar to your own agent tool

**RadarCore** is the engine. Build a host around it:

- CLI
- editor extension
- agent runtime
- daemon (single writer to BlazeDB)

```swift
import RadarCore

let service = AwarenessService()
let reg = try await service.register(
    workspacePath: "/path/to/any/repo",
    agentName: "agent-a",
    task: "auth bug",
    branch: nil,
    worktree: "/path/to/any/repo"
)
let _ = await service.sync(workspacePath: "/path/to/any/repo", registrationId: reg.id)
```

Storage is pluggable via `AwarenessStoreProtocol`. BlazeDB is the default.

Your host decides the command. Your host decides how agents get nudged to sync (hooks, contract, manual). RadarCore just maintains the board.

See [docs/AGENT_DAEMON_INTEGRATION.md](docs/AGENT_DAEMON_INTEGRATION.md).

---

## ProjectBlaze (reference host)

[ProjectBlaze](https://github.com/Mikedan37/AgentCLI) is the private production host Radar was extracted from. **You do not need it to use RadarCore.**

Internally it exposes:

```bash
blaze radar install
blaze radar sync --task "auth bug"
blaze radar note "..."
```

and adds:

- Claude Code contract generation (`CLAUDE.md`)
- Cursor hooks (sync + board on session start / before edit)
- daemon integration via AgentDaemon

That shows how a production host makes Radar automatic. Copy the pattern, not the binary.

---

## Architecture

| Layer | What |
|-------|------|
| **1. Primitive** | Shared state in BlazeDB — identity, location, notes |
| **2. Adoption** | Host wiring — contracts, hooks, CLI — agents actually see it |
| **3. Later** | Merge/review tooling — not Radar |

Layer 1 is the database. Layer 2 is what makes it useful. A good host prints the board before work — it does not block, assign, or decide.

---

## The board

```json
{
  "id": "agent-a12",
  "lastSeen": "10 minutes ago",
  "where": { "branch": "fix-auth", "worktree": "~/repo" },
  "workingOn": "auth bug",
  "notes": ["DB is not the issue"]
}
```

---

## Branches and worktrees

Radar follows the **repository**, not the branch.

Two agents on different branches still share one board:

```bash
# Terminal 1
cd ~/MyApp
git checkout fix-auth
blaze-radar-demo radar sync --task "fix auth"
blaze-radar-demo radar note "Token refresh is failing"

# Terminal 2 — same repo, different branch
cd ~/MyApp
git checkout fix-ui
blaze-radar-demo radar sync --task "fix UI"
```

```
BOARD
agent-a
branch: fix-auth
working: fix auth
notes:
- Token refresh is failing
agent-b
branch: fix-ui
working: fix UI
```

Branch is metadata on the card. The board lives above branches.

| | Tracks |
|---|--------|
| **Git** | Code changes per branch |
| **Radar** | Who is doing what across branches in one repo |

### Worktrees

Git worktrees are separate folders:

```
~/project-auth/   (branch auth)
~/project-ui/     (branch ui)
```

Without care, each folder could get its own `.blaze/radar/` — two whiteboards in two rooms. Hosts resolve worktrees to the **same repository workspace** so agents still share one board. Each card stores **repo root**, **worktree path**, and **branch**, so you can see where another agent's changes actually live.

### Why not just git?

**Git tells you the final diff. Radar tells you the investigation happening before the diff exists.**

---

## Why BlazeDB?

The board is **live coordination state**, not a config file. Multiple agents sync and post notes concurrently. BlazeDB provides safe concurrent access, appendable note history, and fast local storage — no cloud.

---

## Where data lives

| What | Where |
|------|--------|
| Board (shared, per repo) | `<repo>/.blaze/radar/radar.blazedb` |
| Your session (private) | `~/.blaze/radar/` |

One board per git repository root. One agent identity per terminal tab. `done` removes your card from the **active** board; notes stay in the database.

---

## License

MIT. See [LICENSE](LICENSE).
