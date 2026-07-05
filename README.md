# Blaze Radar

Blaze Radar is a local coordination layer for running multiple AI coding agents in the same repository.

If you open three Claude Code sessions on one repo, each one starts with its own context. They do not know another session already investigated a bug, switched branches, or ruled out an approach.

Radar gives those sessions a shared board. Agents can see who else is active, what branch or worktree they are using, and any notes left during the investigation.

Radar creates one board per git repository. Multiple branches and worktrees share that board. Each terminal session gets its own agent card containing its current branch and worktree.

It does not assign work or decide which changes should merge. It only shares context before agents start duplicating effort.

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

# Terminal 2 — same folder, same branch, different session → different card
blaze-radar-demo radar sync --task "frontend cleanup"
blaze-radar-demo radar sync   # sees both cards on one board
```

Each terminal tab gets its own agent identity automatically. To force a new card in the same tab: `blaze-radar-demo radar sync --new`.

Run tests:

```bash
swift test
```

## How agents use it

The demo host exposes `blaze-radar-demo radar …`. Other hosts use their own prefix (`blaze radar …`, `your-tool radar …`). The subcommands are the same.

| Command | Purpose |
|---------|---------|
| `radar sync` | Read the board and refresh your heartbeat |
| `radar sync --task "…"` | Set or update what you are working on |
| `radar sync --new` | Force a new agent card for this terminal tab |
| `radar note "…"` | Append a note to your card |
| `radar done` | Remove your card from the active board |
| `radar status` | Read the board without updating heartbeat |

Use `radar sync --json` for machine-readable output (`registrations`, `relatedAreas`, `fileOverlaps`).

`install` (Claude contract, Cursor hooks) is implemented by the host, not by the demo. See [ProjectBlaze](#projectblaze) for one production example.

A registration on the board (`radar sync --json`) looks like this:

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

Notes from `radar note` append to `discoveredFacts`. Other fields (`negatedHypotheses`, `changedFiles`, etc.) are available for richer host integrations.

## Repository contents

This repo contains:

| Piece | Description |
|-------|-------------|
| **RadarCore** | Shared board state in BlazeDB |
| **Demo host** | `blaze-radar-demo` and `blaze-radar-demo-daemon` |
| **Integration docs** | How to wire RadarCore into your own agent runtime |

There is no universal `radar` binary. Your host chooses the command prefix and how agents are prompted to sync.

## Building your own host

RadarCore is the engine. A typical host adds:

- a CLI or RPC surface
- a **daemon with a single BlazeDB writer** (agents queue writes; avoids concurrent write races)
- optional hooks or contracts so agents sync before work

The demo uses `blaze-radar-demo-daemon` the same way. For a minimal in-process integration:

```swift
import RadarCore

let service = AwarenessService()
let reg = try await service.register(
    workspacePath: "/path/to/repo",
    agentName: "agent-a",
    task: "auth bug",
    branch: nil,
    worktree: "/path/to/repo"
)
let _ = await service.sync(workspacePath: "/path/to/repo", registrationId: reg.id)
```

Hosts must resolve `workspacePath` from any checkout (including worktrees) to the same repository board key. See `RepositoryIdentity.boardKey(from:)` in RadarCore.

Storage is pluggable via `AwarenessStoreProtocol`. BlazeDB is the default.

See [docs/AGENT_DAEMON_INTEGRATION.md](docs/AGENT_DAEMON_INTEGRATION.md).

## ProjectBlaze

[ProjectBlaze](https://github.com/Mikedan37/AgentCLI) is the private production host Radar was extracted from. You do not need it to use RadarCore.

It is one reference implementation that shows how a host can make coordination automatic:

```bash
blaze radar install
blaze radar sync --task "auth bug"
blaze radar note "..."
```

ProjectBlaze also adds Claude Code contract generation, Cursor hooks, and daemon integration via AgentDaemon. Copy the pattern if it fits your setup; the binary itself is not part of this public repo.

## Branches and worktrees

The board answers: *who else is working in this repository?* Each card answers: *where is this agent, and what did they learn?*

| Identity | Key | Meaning |
|----------|-----|---------|
| Repository | `git rev-parse --git-common-dir` | Which board |
| Agent session | terminal tab (`sessionKey`) | Which card |
| Card context | worktree, branch, task, notes | Where that agent is and what they report |

Same repository → same board. Different agent session → different card. Worktree and branch are metadata on the card, not board keys.

Radar is not a substitute for git. Git records code changes. Radar records what agents were investigating before those changes exist.

## Nested git repositories

Worktrees share one board because they share one git identity. **Nested repos do not.**

```
MegaProject/
  .git/                 ← parent repo board
  Frontend/
    .git/               ← separate board
  Backend/
    .git/               ← separate board
```

An agent in `MegaProject/Frontend` coordinates on the **Frontend** board. An agent in `MegaProject/Backend` coordinates on the **Backend** board. They cannot see each other, and that is intentional for v1.

**Coordination boundary = git identity.** Radar does not infer that nested folders are "related." That would require workspace groups, parent-child boards, and cross-repo discovery — out of scope.

| Goal | Where to run agents |
|------|---------------------|
| One board for the whole tree | Run from the **parent repo root** (`MegaProject/`). Cards can still record different worktree paths and tasks. |
| Isolated coordination per sub-repo | Run from each **child repo** (`Frontend/`, `Backend/`). Each gets its own board. |

Example — monorepo-level board with agents working in different areas:

```
MegaProject board
  agent-a   worktree: MegaProject/   task: frontend auth
  agent-b   worktree: MegaProject/   task: backend API
```

A host may eventually warn when a nested `.git` is detected and a parent repo exists. That is a hint, not automatic merging. For now, **you choose which repository identity agents coordinate in** by where you start them.

## Why BlazeDB

The board is live coordination state, not a static config file. Multiple agents sync and append notes concurrently. BlazeDB provides local concurrent access and appendable history without a cloud service.

## Internals

| Layer | Role |
|-------|------|
| **RadarCore** | Board state, sync semantics, note history |
| **Host daemon** | Single writer to BlazeDB; serializes concurrent agent updates |
| **Host CLI / hooks** | Makes agents actually read the board before work |
| **BlazeDB** | On-disk storage |

| What | Where |
|------|--------|
| Board (shared, per repository) | `~/.blaze/radar/workspaces/<repo-hash>/radar.blazedb` |
| Session state (per agent tab) | `~/.blaze/radar/workspaces/<repo-hash>/sessions/` + `agents/` |

`repo-hash` is derived from the git common directory. Legacy boards at `<repo>/.blaze/radar/radar.blazedb` are migrated on first access.

Multiple agents can call sync concurrently; the daemon commits writes in order so every agent sees a consistent board state.

Design philosophy: keep the coordination layer simple and let agents stay smart. A host should surface the board before work starts; it should not block edits, assign tasks, or merge changes.

## License

MIT. See [LICENSE](LICENSE).
