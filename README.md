# Blaze Radar

Blaze Radar is a local coordination layer for running multiple AI coding agents in the same repository.

If you open three Claude Code sessions on one repo, each one starts with its own context. They do not know another session already investigated a bug, switched branches, or ruled out an approach.

Radar gives those sessions a shared board stored in the repository. Agents can see who else is active, what branch or worktree they are using, and any notes left during the investigation.

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

blaze-radar-demo radar sync --task "auth bug"
blaze-radar-demo radar note "DB is not the issue"

# second terminal, same repo
blaze-radar-demo radar sync
```

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
| `radar note "…"` | Append a note to your card |
| `radar done` | Remove your card from the active board |
| `radar status` | Read the board without updating heartbeat |

`install` (Claude contract, Cursor hooks) is implemented by the host, not by the demo. See [ProjectBlaze](#projectblaze) for one production example.

A card on the board looks like this:

```json
{
  "id": "agent-a12",
  "lastSeen": "10 minutes ago",
  "where": { "branch": "fix-auth", "worktree": "~/MyApp" },
  "workingOn": "auth bug",
  "notes": ["DB is not the issue"]
}
```

## Repository contents

This repo contains:

| Piece | Description |
|-------|-------------|
| **RadarCore** | Shared board state in BlazeDB |
| **Demo host** | `blaze-radar-demo` and `blaze-radar-demo-daemon` |
| **Integration docs** | How to wire RadarCore into your own agent runtime |

There is no universal `radar` binary. Your host chooses the command prefix and how agents are prompted to sync.

The board is stored at the git repository root:

```
<repo>/.blaze/radar/radar.blazedb
```

## Building your own host

RadarCore is the engine. A typical host adds:

- a CLI or RPC surface
- a daemon that owns the BlazeDB writer
- optional hooks or contracts so agents sync before work

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

The board belongs to the repository, not to a branch. Two agents on `fix-auth` and `fix-ui` in the same repo read the same board. Branch name is stored on each card as metadata.

Git worktrees are separate directories. A host should resolve them to the same repository workspace so agents do not end up with separate boards. Each card records the worktree path so you can see where another agent's checkout lives.

Radar is not a substitute for git. Git records code changes. Radar records what agents were investigating before those changes exist.

## Why BlazeDB

The board is live coordination state, not a static config file. Multiple agents sync and append notes concurrently. BlazeDB provides local concurrent access and appendable history without a cloud service.

## Internals

| Layer | Role |
|-------|------|
| **RadarCore** | Board state, sync semantics, note history |
| **Host** | CLI, daemon, hooks — makes agents actually read the board |
| **BlazeDB** | On-disk storage at `<repo>/.blaze/radar/radar.blazedb` |

Per-agent session state (identity, last sync snapshot) lives in `~/.blaze/radar/`. `done` removes your card from the active board; notes remain in the database.

Design philosophy: keep the coordination layer simple and let agents stay smart. A host should surface the board before work starts; it should not block edits, assign tasks, or merge changes.

## License

MIT. See [LICENSE](LICENSE).
