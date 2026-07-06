# Blaze Radar

Blaze Radar is a **local coordination library** for running multiple AI coding agents on the same git repository.

If you open three Claude Code sessions on one repo, each one starts with its own context. They do not know another session already investigated a bug, switched branches, or ruled out an approach.

Radar gives those sessions a **shared board**: who is active, what branch/worktree they are on, and notes left during the investigation. It does not assign work or decide what merges. It shares context so agents stop duplicating effort.

**This repo ships `RadarCore`**, the board engine. It does not ship a universal `radar` binary. Your host (CLI, daemon, IDE plugin) chooses the command prefix and how agents are prompted to sync.

Three layers. Keep them separate:

| Layer | Role |
|-------|------|
| **RadarCore** | Coordination model: register, sync, notes, overlap detection |
| **Host (daemon or app)** | Ownership and lifecycle: one process holds the BlazeDB writer |
| **BlazeDB** | Default persistence: durable local board per repository identity (swap via `AwarenessStoreProtocol`) |

You do not need *our* daemon. You need **one owner for shared mutable state**. If your host already provides that, use it.

**Core invariant:** session JSON under `~/.blaze/radar/.../agents/` is a **cache** (terminal binding, sync cursor). **`radar.blazedb` is the source of truth.** Local session files may disappear; the board still has the card.

---

## Architecture in one picture

```
  Terminal A          Terminal B          Terminal C
  (agent session)     (agent session)     (agent session)
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │  RPC / CLI
                           ▼
              ┌────────────────────────────┐
              │  Host process (your choice)  │  ← owns the single BlazeDB writer
              │  • blaze-radar-demo-daemon   │  ← public demo (this repo)
              │  • AgentDaemon (private)     │
              │  • your own long-lived app   │
              └─────────────┬──────────────┘
                            │  calls into
                            ▼
              ┌────────────────────────────┐
              │  RadarCore (this repo)     │  ← coordination logic only
              │  AwarenessService, store   │
              └─────────────┬──────────────┘
                            │  persists to
                            ▼
              ┌────────────────────────────┐
              │  BlazeDB                   │  ← one file per repo identity
              │  ~/.blaze/radar/.../       │
              │    radar.blazedb           │
              └────────────────────────────┘
```

**Default local stack:** agents → host → **RadarCore** → **BlazeDB**.

Embedded or cloud hosts can skip the daemon and/or swap the store. See [Three ways to integrate](#three-ways-to-integrate).

That answers: *who is working on what, what did they learn, what changed?*

---

## What is in this repo?

### What is public?

This repository contains everything needed to run Radar:

- **RadarCore** (library)
- **blaze-radar-demo** (example CLI)
- **blaze-radar-demo-daemon** (example host process)

**ProjectBlaze**, **AgentCLI**, and **AgentDaemon** are not part of this repository. They are the private production host Radar was extracted from.

The demo CLI exists so you can try the full flow without ProjectBlaze:

```bash
blaze-radar-demo-daemon &
blaze-radar-demo radar sync --task "auth bug"
blaze-radar-demo radar note "Database path ruled out"
```

ProjectBlaze's private `blaze radar ...` commands call the same RadarCore APIs through AgentDaemon. Different binary, same board engine.

| Piece | Public? | What it is | How it fits |
|-------|---------|------------|-------------|
| **RadarCore** | Yes | Swift library: register agents, sync board, append notes, detect overlaps | The product. All hosts call into this. |
| **blaze-radar-demo** | Yes | Example CLI (`blaze-radar-demo radar …`) | Public substitute for private `blaze radar …`. Same subcommands, different binary prefix. |
| **blaze-radar-demo-daemon** | Yes | Minimal local host that owns BlazeDB writes for the demo CLI | Public substitute for AgentDaemon. Start this before running the demo CLI. |
| **AgentDaemon** | No | Long-lived process in [ProjectBlaze](https://github.com/Mikedan37/AgentCLI) that owns the BlazeDB writer, runs git polling, exposes Radar over the agent socket | Production host Radar was extracted from. Same role as `blaze-radar-demo-daemon`, different wire protocol (BlazeBinary) and broader agent runtime. |
| **AgentCLI / `blaze`** | No | Private CLI in ProjectBlaze (`blaze radar sync`, `blaze radar note`, `blaze radar install`, …) | Production CLI that talks to AgentDaemon. Calls the same RadarCore APIs as `blaze-radar-demo`; adds install hooks, doctor, and Claude/Cursor contract generation. |

There is no contradiction between “you need a daemon” and “you don’t need AgentDaemon”:

- You need **one write-owning process** per machine when multiple agent sessions hit the board at once.
- You do **not** need ProjectBlaze or AgentDaemon. Use **blaze-radar-demo-daemon** to try the flow here, embed RadarCore in your own app, or build your own host.

### The demo stack is complete for coordination

Cloning this repo gives you the full core loop today:

```
blaze-radar-demo → blaze-radar-demo-daemon → RadarCore → BlazeDB
```

That path uses the **same board engine** as private production. It proves the same behavior:

- multiple agent sessions on one repository
- shared board with one card per terminal session
- `sync` (read board, heartbeat, git/branch awareness)
- `note` (append findings)
- branch and worktree on each card
- persistence in `radar.blazedb` across daemon restarts

ProjectBlaze does **not** change Radar semantics. It does not add a different board model or smarter coordination. It adds **automation and polish** around the same RadarCore APIs.

**RadarCore solves shared workspace awareness. Hosts decide how automatic that workflow becomes.** ProjectBlaze is one host implementation, not a required upgrade.

| | Public demo (this repo) | ProjectBlaze (private) |
|--|-------------------------|-------------------------|
| Board engine | RadarCore | RadarCore (same) |
| Persistence | BlazeDB | BlazeDB (same) |
| Sync / note model | Same | Same |
| Wire protocol | JSON over Unix socket | BlazeBinary over agent socket |
| Agent prompting | Manual (you or Claude) | `blaze radar install` + hooks/contracts |
| Extra tooling | Demo CLI only | Doctor, session recovery polish, fix/plan/execute runtime |

**What the demo does not ship** (because it lives in private ProjectBlaze):

- automatic Claude/Cursor contract installation
- generated `CLAUDE.md` radar instructions
- hooks that force agents to sync before work
- `blaze radar doctor` checks
- production session recovery polish (terminal rebind when cache files are gone)
- broader agent runtime commands outside Radar (`fix`, `plan`, `execute`, …)

None of that changes what the board *is*. It changes how often agents hit the board without you asking.

### Using the demo with Claude Code manually

You do not need ProjectBlaze to coordinate agents. Tell Claude what to run:

```
Before starting work in this repo, run:
  blaze-radar-demo radar sync --task "<what you are doing>"

When you discover something worth sharing, run:
  blaze-radar-demo radar note "<finding>"
```

Open a second terminal tab, run `blaze-radar-demo radar sync` there, and Claude sees the first session's task and notes on the shared board.

ProjectBlaze automates those steps with `blaze radar install` and editor hooks. The underlying coordination is identical.

---

## Why BlazeDB?

Radar state is **shared runtime data**: several terminals may sync, note, and heartbeat concurrently on the same repository.

A JSON file in the repo (or one `board.json` per workspace) breaks down immediately:

- two writers at once → last write wins or corrupted file
- no durable append history for findings
- no safe place for git observation snapshots alongside agent cards

**BlazeDB is the default store because it matches how embedded databases are supposed to work.**

| Property | Why Radar cares |
|----------|-----------------|
| **Single writer per file** | Normal for SQLite, LMDB, and BlazeDB, not a Radar quirk. One process opens `radar.blazedb` and serializes mutations. |
| **Local, no server** | Coordination stays on the developer machine; no Redis/Postgres to run. |
| **Durable + append-friendly** | Findings and git observations accumulate; the board survives daemon restarts. |
| **Typed collections** | Agents, findings, git observations, sync checkpoints: separate shapes, one DB file per repo. |

`BlazeDBClientPool` enforces one client per workspace board key. **Opening the same `radar.blazedb` from multiple processes will crash or corrupt data.** That is why a host process exists: not to make Radar “smarter”, but to be the **one writer**.

See **Core invariant** above: never treat session files as the board. Hosts that implement identity recovery rebind a terminal to an existing card by reading `radar.blazedb`, not by hoping `session.json` survived.

`AwarenessStoreProtocol` is pluggable: tests use `JSONAwarenessStore()`. Production uses `BlazeDBAwarenessStore`.

---

## Why a daemon? (And when you can skip a separate one)

Think in two layers:

| | Coordination **logic** | Coordination **process** |
|--|------------------------|---------------------------|
| **What** | Board rules, sync semantics, overlap detection | Long-lived owner of the BlazeDB writer |
| **Where** | **RadarCore** (this repo) | **Your host**: demo daemon, AgentDaemon, or embedded app |
| **Analogy** | Business logic | App server in front of a database |

### When a separate daemon **is** necessary

- Multiple **short-lived CLIs** (one per terminal tab) all call `radar sync` / `radar note`
- Each CLI exits after the command; something must stay alive and hold the DB connection
- **One daemon, many clients**, same pattern as language servers or build daemons

ProjectBlaze uses **AgentDaemon** because it already is that local runtime for fix/plan/execute. Radar is another capability on the same bus, not a reason to invent a second daemon product.

### When a separate daemon is **not** necessary

- Your tool is already **one long-lived process** (IDE plugin, custom agent runner, single GUI app)
- That process can call `AwarenessService()` directly and own the only BlazeDB client
- You still respect single-writer rules; you just do not spawn a second binary

### What the demo stack is for

`blaze-radar-demo` + `blaze-radar-demo-daemon` are the **public, self-contained** way to run the full CLI → host → RadarCore → BlazeDB flow. Same board semantics as production, simpler wire protocol (JSON over Unix socket). See [The demo stack is complete for coordination](#the-demo-stack-is-complete-for-coordination) above.

---

## Three ways to integrate

The same coordination model fits different hosts. Pick the shape that matches your runtime.

**Claude Code style** (short-lived CLI tabs, one machine):

```
CLI tab A / CLI tab B
        ↓
   daemon (write owner)
        ↓
    RadarCore
        ↓
    BlazeDB (default local store)
```

**IDE or desktop app** (already one long-running process):

```
IDE / agent runner / desktop app
        ↓
    RadarCore
        ↓
    BlazeDB (default) or your store
```

No separate daemon. Your app holds one `AwarenessService` and serializes board writes internally.

**Cloud agent service** (shared board across machines):

```
agent service (your API)
        ↓
    RadarCore
        ↓
Postgres / Redis / your backend
```

Implement `AwarenessStoreProtocol` behind the service. The coordination model stays the same; only persistence and transport change.

BlazeDB remains the **default and recommended** local implementation: single-writer semantics, durable findings, no server to run. Use it when your host runs on the developer machine. Swap the store when your truth lives somewhere else.

---

## Using RadarCore without a daemon

If your application is already long-running, call RadarCore directly.

An IDE extension, agent runner, or desktop app can own the board itself. No daemon, no CLI, no socket. Your process holds one `AwarenessService`, which holds one store connection.

```swift
import RadarCore

final class MyAgentRuntime {
    let service = AwarenessService()  // default: BlazeDBAwarenessStore

    func startAgent(repo: String) async throws {
        let agent = try await service.register(
            workspacePath: repo,
            agentName: "agent-a",
            task: "fix auth",
            branch: nil,
            worktree: repo
        )

        _ = try await service.update(
            workspacePath: repo,
            registrationId: agent.id,
            patch: UpdateAgentRequest(
                workspacePath: repo,
                registrationId: agent.id.uuidString,
                discoveredFacts: ["Database path ruled out"]
            )
        )

        let board = await service.getActiveWork(workspacePath: repo)
        // board.registrations: all active cards for this repo
    }
}
```

Rules are the same as with a daemon: **one write owner per board**. If you spawn multiple processes that each open `radar.blazedb`, you will corrupt data. Embed RadarCore in the process that already owns your agent lifecycle.

---

## Using a different store

RadarCore depends on `AwarenessStoreProtocol`, not on BlazeDB specifically.

```swift
let service = AwarenessService(store: MyCustomStore())
```

The protocol surface:

```swift
protocol AwarenessStoreProtocol {
    func load(workspacePath: String) async throws -> [AgentRegistration]
    func save(workspacePath: String, registrations: [AgentRegistration]) async throws
    func upsert(workspacePath: String, registration: AgentRegistration) async throws
    func find(workspacePath: String, id: UUID) async throws -> AgentRegistration?
    func activeRegistrations(workspacePath: String) async throws -> [AgentRegistration]
    func recordSync(workspacePath: String, agentId: UUID, at: Date) async throws
}
```

Shipped implementations:

| Store | Use when |
|-------|----------|
| `BlazeDBAwarenessStore` | Local board on the developer machine (production default) |
| `JSONAwarenessStore` | Tests, prototypes, single-process experiments |

Your own backend (Postgres, Redis, SQLite, etc.) implements the same protocol. `AwarenessService` does not change. Register, sync, update, overlap detection, and git refresh semantics stay identical.

---

## Dogfood example

During a Seeker audit, two Claude Code sessions were started against the same repository.

Agent A investigated onboarding, upload, and analytics issues. It recorded findings as it worked.

Agent B joined later. Instead of starting from an empty context window, it synced the board first and saw what Agent A was already investigating and what had been discovered.

Radar did not decide what to fix, merge branches, or review code. It only preserved workspace awareness between otherwise isolated sessions.

The interesting failures while building Radar were not model failures. They were normal systems problems: stale contracts, process lifecycle, identity recovery, and persistence bugs.

---

## Quick demo

```bash
git clone https://github.com/Mikedan37/blaze-radar.git
cd blaze-radar
swift build -c release
export PATH="$PWD/.build/release:$PATH"
blaze-radar-demo-daemon &
```

In any git repository:

```bash
cd ~/SomeRandomRepo

# Terminal 1
blaze-radar-demo radar sync --task "auth bug"
blaze-radar-demo radar note "DB is not the issue"

# Terminal 2: same folder, different session → different card, same board
blaze-radar-demo radar sync --task "frontend cleanup"
blaze-radar-demo radar sync   # sees both cards and Terminal 1's note
```

Each terminal tab gets its own agent identity automatically. Force a new card in the same tab: `blaze-radar-demo radar sync --new`.

```bash
swift test
```

---

## How agents use it

The demo host exposes `blaze-radar-demo radar …`. Other hosts use their own prefix (`blaze radar …`, `your-tool radar …`). Subcommands are the same.

| Command | Purpose |
|---------|---------|
| `radar sync` | Read the board and refresh your heartbeat |
| `radar sync --task "…"` | Set or update what you are working on |
| `radar sync --new` | Force a new agent card for this terminal tab |
| `radar note "…"` | Append a note to your card |
| `radar done` | Remove your card from the active board |
| `radar status` | Read the board without updating heartbeat |

Use `radar sync --json` for machine-readable output.

`install` (Claude contract, Cursor hooks) is a **ProjectBlaze host feature**, not part of this repo. The demo supports the same sync/note loop with manual prompting. See [ProjectBlaze](#projectblaze-private-host-reference).

Example registration (`radar sync --json`):

```json
{
  "agentName": "agent-a12",
  "task": "auth bug",
  "branch": "fix-auth",
  "worktree": "/Users/you/MyApp",
  "status": "active",
  "discoveredFacts": ["DB is not the issue"],
  "lastSeen": "2026-07-05T20:04:30Z"
}
```

Notes from `radar note` append to `discoveredFacts`.

---

## Talking to the demo daemon

`blaze-radar-demo-daemon` exposes a small **JSON RPC** interface over a **Unix socket** (default: `/tmp/blaze_radar.sock`, override with `BLAZE_RADAR_SOCKET`).

The demo CLI is only a wrapper around that protocol:

```
blaze-radar-demo radar sync
        ↓
JSON request
        ↓
blaze-radar-demo-daemon
        ↓
RadarCore
```

**Framing:** one request per line, newline-terminated:

```
<json>\n
```

**Request envelope:**

```json
{"method":"<name>","params":{...}}
```

**Response envelope:**

```json
{"success":true,"result":{...}}
```

or on failure:

```json
{"success":false,"error":"message","result":null}
```

**Methods** (see `RadarDemoClient/RadarDaemonClient.swift` for full shapes):

| `method` | Purpose |
|----------|---------|
| `register` | Create or resume an agent card |
| `active` | Read the board (`getActiveWork`) |
| `sync` | Sync board + heartbeat |
| `update` | Append notes / patch card |
| `refresh` | Update task, branch, worktree |
| `done` | Mark card done |

**Example: sync after register**

```json
{"method":"sync","params":{"workspacePath":"/path/to/repo","registrationId":"F221AAA7-BEFA-4AC2-ACE5-BC2A026AB34E"}}
```

**Example: append a note**

```json
{"method":"update","params":{"workspacePath":"/path/to/repo","registrationId":"F221AAA7-BEFA-4AC2-ACE5-BC2A026AB34E","discoveredFacts":["Database path ruled out"]}}
```

Connect with any Unix socket client, send one line, read one line back. One connection per request.

This protocol is **demo-only**. ProjectBlaze's AgentDaemon uses **BlazeBinary** framed messages over `/tmp/blaze_agent.sock` (different client, not compatible). If you build your own host, pick whatever transport fits: HTTP, gRPC, Unix sockets, or skip RPC and call `AwarenessService` in-process.

**Where to plug the wire:**

| Goal | What to use |
|------|-------------|
| Try it interactively | `blaze-radar-demo` CLI |
| Script against the public daemon | JSON RPC on `/tmp/blaze_radar.sock` |
| Embed in your app | `AwarenessService()` directly |
| Build a distributed host | Your own RPC + `AwarenessStoreProtocol` if needed |

---

## Building a daemon-backed host

If you have **short-lived CLIs** (like `blaze-radar-demo` or `blaze radar`), add a long-lived process that owns writes and expose a thin RPC layer. The demo stack is the smallest example; ProjectBlaze's AgentDaemon is the production one.

```swift
import RadarCore

// Inside your daemon's request handler (one shared instance):
let service = AwarenessService()  // BlazeDBAwarenessStore by default

let reg = try await service.register(
    workspacePath: "/path/to/repo",
    agentName: "agent-a",
    task: "auth bug",
    branch: nil,
    worktree: "/path/to/repo"
)
let _ = await service.sync(workspacePath: "/path/to/repo", registrationId: reg.id)
```

Your host adds:

- CLI or RPC surface for agents
- **Single process** that holds `BlazeDBClientPool` when using the default store
- Optional hooks/contracts so agents sync before work

Wire protocol (BlazeBinary, JSON, gRPC) is **your** choice. Domain logic stays in RadarCore.

See **Using RadarCore without a daemon** and **Using a different store** above for embedded and custom-backend setups.

Full wiring notes: [docs/AGENT_DAEMON_INTEGRATION.md](docs/AGENT_DAEMON_INTEGRATION.md).

---

## Why not a Kanban board?

Kanban tracks planned work. Radar tracks **live agent context**.

A ticket might say: *Fix authentication.*

Radar answers: *Another session is already debugging auth on `fix-token`. It checked the database path and ruled it out ten minutes ago.*

Jira, Slack, and Kanban assume a human decides to check them. Agents start stateless, read local context, execute, and move on. Radar is a machine-readable coordination primitive for workspace awareness before they act.

Radar does not manage agents. It gives them the environmental context humans naturally have in a shared office.

---

## ProjectBlaze (private host reference)

[ProjectBlaze](https://github.com/Mikedan37/AgentCLI) is a **private** monorepo. It is not part of this repository and is not required to use Radar.

Think of it as the **automatic seatbelt** around the same engine: RadarCore is the coordination model; ProjectBlaze wires that model into Claude Code and Cursor with less manual prompting.

```bash
blaze radar install      # writes contract + hooks (not in this repo)
blaze radar sync --task "auth bug"
blaze radar note "..."
```

ProjectBlaze routes `blaze radar *` through **AgentDaemon** into the same RadarCore APIs this repo defines.

**The production `blaze` binary is not available here.** Use `blaze-radar-demo` + `blaze-radar-demo-daemon`, prompt Claude manually, or integrate RadarCore directly.

---

## Branches, worktrees, and nested repos

Same git repository identity → **same board**. Different agent session → **different card**. Branch and worktree are fields on the card, not board keys.

Radar is not a substitute for git. Git records code changes. Radar records what agents were investigating before those changes exist.

**Worktrees** (`repo-auth/`, `repo-ui/`) share one board (same `.git` common directory).

**Nested repos** (`MegaProject/Frontend/.git`, `MegaProject/Backend/.git`) get **separate boards**, intentional. Start agents from the same repository boundary if you want shared context.

---

## On-disk layout

| What | Role |
|------|------|
| `radar.blazedb` | **Source of truth**: agent cards, findings, git observations |
| `agents/`, `sessions/` | **Cache**: per-tab session binding and sync cursor (may be rebuilt from the board) |

Path: `~/.blaze/radar/workspaces/<repo-hash>/`

`<repo-hash>` is derived from the git common directory, so branches and worktrees share one board file.

---

## Design & evaluation

Radar is **state feedback**, not agent management. The control-theory framing and benchmark pass/fail criteria:

| Doc | Contents |
|-----|----------|
| [docs/RadarDynamics.md](docs/RadarDynamics.md) | Phase space, exploration vs oscillation, damping analogy |
| [docs/BENCHMARK.md](docs/BENCHMARK.md) | Multi-agent trial harness + scorer (scripts in [AgentCLI](https://github.com/Mikedan37/AgentCLI/tree/main/scripts)) |

**One line:** Proximity in workspace ≠ collision. What matters is velocity through explored space.

---

## License

MIT. See [LICENSE](LICENSE).
