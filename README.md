# Blaze Radar

Blaze Radar is a local coordination layer for running multiple AI coding agents in the same repository.

If you open three Claude Code sessions on one repo, each one starts with its own context. They do not know another session already investigated a bug, switched branches, or ruled out an approach.

Radar gives those sessions a shared board. Agents can see who else is active, what branch or worktree they are using, and any notes left during the investigation.

Radar creates one board per git repository identity. Branches and git worktrees share that board because they point back to the same underlying repository. Each terminal session gets its own agent card containing its current branch and worktree.

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

Use `radar sync --json` for machine-readable output.

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

Notes from `radar note` append to `discoveredFacts`.

## Repository contents

| Piece | Description |
|-------|-------------|
| **RadarCore** | Shared board state |
| **Demo host** | `blaze-radar-demo` and `blaze-radar-demo-daemon` |
| **Integration docs** | How to wire RadarCore into your own agent runtime |

There is no universal `radar` binary. Your host chooses the command prefix and how agents are prompted to sync.

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

## Why not a Kanban board?

Kanban tracks planned work. Radar tracks live agent context.

A ticket might say: *Fix authentication.*

Radar answers: *Another session is already debugging auth on `fix-token`. It checked the database path and ruled it out ten minutes ago.*

Jira, Slack, and Kanban assume a human decides to check them, understands social context, and updates them intentionally. Agents start stateless, read local context, execute, and move on. Radar is a machine-readable coordination primitive for those sessions — workspace awareness before they act.

Radar does not manage agents. It gives them the environmental context humans naturally have in a shared office.

## Why not a JSON file?

Radar is shared runtime state. Multiple agents may sync and write notes at the same time.

BlazeDB gives Radar:

- serialized writes through a host daemon
- local storage
- appendable history
- no server requirement

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

Same git repository identity → same board. Different agent session → different card. Branch and worktree path are fields on the card, not board keys.

Radar is not a substitute for git. Git records code changes. Radar records what agents were investigating before those changes exist.

## Nested git repositories

Radar's boundary is git identity.

Worktrees:

```
repo-auth/
repo-ui/
```

share one board because they belong to the same git repository.

Nested repositories:

```
MegaProject/
  .git/
  Frontend/
    .git/
  Backend/
    .git/
```

create separate boards. This is intentional. If you want agents to share context, start them from the same repository boundary.

## Internals

| What | Where |
|------|--------|
| Board (per repository identity) | `~/.blaze/radar/workspaces/<repo-hash>/radar.blazedb` |
| Session state (per agent tab) | `~/.blaze/radar/workspaces/<repo-hash>/sessions/` + `agents/` |

`repo-hash` is derived from the git common directory.

## License

MIT. See [LICENSE](LICENSE).
