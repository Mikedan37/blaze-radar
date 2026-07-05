# AgentDaemon Integration

## Coordination logic vs coordination process

These are different things. Don't conflate them.

| | Coordination logic | Coordination process |
|--|-------------------|---------------------|
| **What** | Shared state, history, related-area detection, sync semantics | One long-lived owner of the BlazeDB writer |
| **Where** | `RadarCore` (this repo) | `AgentDaemon` (private) |
| **Analogy** | Business logic | App server in front of a database |

The minimum architecture for parallel-agent awareness:

```
agents → shared interface → RadarCore → BlazeDB
```

That solves the stated problem: *who is doing what, what did they learn, what changed?*

Production in ProjectBlaze adds a host because BlazeDB is built around **one writer, serialized mutations**:

```
Claude / Cursor agents
        ↓
    blaze radar *
        ↓
   AgentDaemon          ← single BlazeDB writer, background poller
        ↓
    RadarCore            ← AwarenessService (logic only)
        ↓
     BlazeDB             ← radar.blazedb
```

## What AgentDaemon adds (for coordination only)

Not intelligence. Not the radar algorithm.

1. **One long-lived process** — agents don't each open BlazeDB independently
2. **Background observation** — `AwarenessGitPoller`, heartbeats, stale cleanup
3. **Stable API** — agents say `blaze radar sync`; daemon hides schema, paths, locking

ProjectBlaze already routes all agent interactions through one local runtime. Radar is another capability on that bus — not a reason to invent a second daemon product.

## SwiftPM dependency

**Monorepo (local path):**

```swift
.package(path: "../../blaze-radar"),
// ...
.target(name: "AgentDaemon", dependencies: [
    .product(name: "RadarCore", package: "blaze-radar"),
    // ...
])
```

**Published dependency:**

```swift
.package(url: "https://github.com/Mikedan37/blaze-radar.git", from: "1.0.0"),
```

## Host process wiring

AgentDaemon holds **one** shared `AwarenessService` and **one** `AwarenessGitPoller`:

```swift
import RadarCore

let awareness = AwarenessService()  // default: BlazeDBAwarenessStore
let poller = AwarenessGitPoller(service: awareness)
poller.start()

// BlazeBinary handlers decode RPC and delegate:
let reg = try await awareness.register(
    workspacePath: path,
    agentName: name,
    task: task,
    branch: branch,
    worktree: worktree
)
```

Wire protocol (BlazeBinary encode/decode) stays in AgentDaemon. Domain logic stays in RadarCore.

## State ownership (v0.2)

Do not put agent identity or sync cursors in the repo.

| | Location | Contents |
|--|----------|----------|
| **Shared** | `<workspace>/.blaze/radar.blazedb` | Board, findings, git observations |
| **Private** | `~/.blaze/radar/workspaces/{hash}/agents/{id}/` | `session.json`, `sync.json` |

AgentCLI resolves sessions by `--agent` name. `register` resumes unless `--new`. Multiple parallel agents on one monorepo each get their own folder under `~/.blaze/radar/`.

## Storage

- Production: `BlazeDBAwarenessStore` → `<workspace>/.blaze/radar.blazedb`
- Tests: inject `JSONAwarenessStore()` via `AwarenessService(store:)`

`BlazeDBClientPool` ensures one client per workspace — multiple clients on the same file will crash.

## Demo stack (optional)

For contributors without AgentDaemon:

```bash
swift build -c release
export PATH="$PWD/.build/release:$PATH"
blaze-radar-demo-daemon &
cd /path/to/git-repo
blaze-radar-demo radar sync --task "auth bug"
blaze-radar-demo radar note "example finding"
blaze-radar-demo radar sync   # second terminal — see the note
```

Same host pattern (one process owns writes), different wire protocol (JSON over Unix socket). **Not** the product — a way to try RadarCore without ProjectBlaze.
