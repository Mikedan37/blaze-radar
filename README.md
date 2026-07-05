# Blaze Radar

**Claude and Cursor sessions don't know each other exist. Radar puts a local board in the repo. Every agent checks the board before work and leaves notes.**

A whiteboard. Not a project manager. Not Jira for bots.

**The bet:** dumb coordination layer → smart workers with context.

---

## Any git repo + a host CLI

Radar works in **any git repository**. The board is created wherever you run it:

```
~/SomeRandomRepo/
  .blaze/
    radar/
      radar.blazedb
```

You need two things:

1. **A git repo** (the workspace — portable, repo-local)
2. **A Radar host CLI** (the executable — *not* a universal `radar` binary)

```
any git repo  +  host CLI  =  Radar works
```

The command prefix depends on the host. There is no standalone `radar` command in this repo.

| Host | Prefix |
|------|--------|
| **Demo** (this repo, after `swift build`) | `blaze-radar-demo radar …` |
| **ProjectBlaze** | `blaze radar …` |
| **Your integration** | whatever wraps RadarCore |

---

## Try it (demo host, any repo)

```bash
git clone https://github.com/Mikedan37/blaze-radar.git
cd blaze-radar && swift build -c release
export PATH="$PWD/.build/release:$PATH"
blaze-radar-demo-daemon &

cd ~/SomeRandomRepo    # any git repo — not blaze-radar itself

blaze-radar-demo radar sync --task "auth bug"
blaze-radar-demo radar note "Token refresh failing. DB is fine."

# second terminal, same repo
blaze-radar-demo radar sync
```

---

## Use it (ProjectBlaze host, any repo)

```bash
# once per machine
cd AgentCLI && make install && blaze daemon start

# once per repo you care about
cd ~/SomeRandomRepo
blaze radar install

blaze radar sync --task "fix auth"
blaze radar note "DB is not the issue"
blaze radar sync
blaze radar done
```

`install` writes `CLAUDE.md` rules, `.cursor/hooks.json`, and `.blaze/radar/` into **that repo**. Without it, agents have to remember to sync — that's "please check the wiki" again.

---

## Commands

Subcommands are the same on every host. Replace `<host>` with your prefix.

| When | Command |
|------|---------|
| Start / read board | `<host> radar sync` |
| Say what you're on | `<host> radar sync --task "auth bug"` |
| Learned something | `<host> radar note "..."` |
| Changed focus | `<host> radar sync --task "new task"` |
| Finished | `<host> radar done` |
| Peek (no heartbeat) | `<host> radar status` |
| Wire adapters | `<host> radar install` *(ProjectBlaze and other full hosts)* |

**Demo:** `blaze-radar-demo radar sync`  
**ProjectBlaze:** `blaze radar sync`

---

## Embed RadarCore

Build your own host, point it at any repo:

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

See [docs/AGENT_DAEMON_INTEGRATION.md](docs/AGENT_DAEMON_INTEGRATION.md).

---

## Architecture

| Layer | What |
|-------|------|
| **1. Primitive** | Shared state in BlazeDB — identity, location, notes |
| **2. Adoption** | `install`, Claude contract, Cursor hooks — agents actually see it |
| **3. Later** | Merge/review tooling — not Radar |

Layer 1 is the database. Layer 2 is what makes it useful. Hooks print the board — they do not block, assign, or decide.

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

## Why BlazeDB?

The board is **live coordination state**, not a config file. Multiple agents sync and post notes concurrently. BlazeDB provides safe concurrent access, appendable note history, and fast local storage — no cloud.

```
<any-repo>/.blaze/radar/radar.blazedb
```

---

## Where data lives

| What | Where |
|------|--------|
| Board (shared, per repo) | `<repo>/.blaze/radar/radar.blazedb` |
| Your session (private) | `~/.blaze/radar/` |

One board per git repo. One agent identity per terminal tab. `done` removes your card from the **active** board; notes stay in the database.

---

## License

MIT. See [LICENSE](LICENSE).
