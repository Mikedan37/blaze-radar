# Blaze Radar

**Add awareness to your existing AI coding agents.**

Multiple Claude Code or Cursor agents working in one repo cannot see each other. One window spends an hour on auth while another starts from zero, repeats the same investigation, or edits the same files without knowing anyone is already there.

Radar gives them a shared local workspace board and installs the instructions and hooks that make them check it automatically.

---

## Install once

In your git repo:

```bash
radar install
```

Your CLI may prefix the command (`blaze radar install` in ProjectBlaze). Same idea everywhere: one install per repo.

That sets up:

- A managed block in `CLAUDE.md` with rules for when to sync, when to record findings, and what to do before edits
- Cursor hooks for session start, before edits, and before deploys
- Local board storage under `.blaze/radar/`

The contract is the point. It does not ask agents to "remember to update the wiki." It tells them: sync at session start, record discoveries as you go, check the board before changing approach.

After install, normal use should not feel like a checklist you maintain by hand.

**What happens automatically:**

- A new agent session starts → syncs and reads the board
- An agent learns something mid-investigation → records it (because `CLAUDE.md` says to)
- Before edits or deploys → checks for overlap
- Another agent opens later → sees existing findings first

---

## What it looks like

**10:00 — Claude window 1**

```
Working: fix auth
Found:
  Token refresh is failing. Database is fine.
```

**10:20 — Claude window 2 opens**

```
Radar:
  Another agent is already working on auth.
Known:
  Token refresh is failing. Database is fine.
```

Claude changes direction instead of redoing the investigation.

Will the second agent stop nuking the first agent's work? That is what Radar is for.

---

## Try it with two Claude sessions

This is the proof. Hooks are great, but people trust what they can paste into a window.

**Prerequisites:** `radar install` in the repo, Radar CLI on PATH, daemon running. Use a **new terminal tab** for each window so each session gets its own agent identity.

Open the same repository in two Claude Code windows.

### Claude window 1

Paste:

```text
You are Agent A.

Start by checking Radar:
- run radar sync
- read the active board

Register that you are investigating authentication.

Record anything important you discover with:
radar update --found "..."

Investigate why authentication is failing.
```

After it finds something:

```text
Record your current finding in Radar.
```

### Claude window 2

Open a **second terminal tab**, start Claude in the same repo, paste:

```text
You are Agent B.

Before touching code:
- run radar sync
- read every active agent and finding

Another agent may already be investigating this.

Your job:
1. Check what Agent A has learned
2. Avoid repeating completed investigation
3. Either continue from their findings or choose a separate area

Do not edit until you understand the current board.
```

### Expected behavior

**Without Radar:** Agent B starts debugging auth from scratch.

**With Radar:** Agent B sees:

```
Agent A:
  Found: Token refresh is failing. Database is fine.
```

and continues from there.

If window 2 only sees itself, open a new terminal tab (same session = same agent) or run `radar sync --new`.

---

## How Radar becomes automatic

Once the manual test works, you should not need those prompts every time.

**Claude Code**

```
CLAUDE.md (from radar install)
        ↓
agent reads Radar rules at session start
        ↓
runs sync before editing
        ↓
records findings when the contract says to
```

**Cursor**

```
.cursor/hooks.json (from radar install)
        ↓
session start  →  radar sync
before edit    →  collision check
before deploy  →  active work check
```

Hooks are advisory. They surface context; they do not block your editor. Disable with `BLAZE_RADAR_HOOKS=0` if needed.

---

## Manual commands

For debugging or integrators. Day to day, the contract and hooks should handle this.

| When | Command |
|------|---------|
| Start of session | `radar sync` |
| Learned something | `radar update --found "..."` |
| Ruled something out | `radar update --ruled-out "..."` |
| Step back | `radar yield` |
| Finished | `radar done` |
| Dashboard | `radar status` |

---

## Try the board without agents (demo)

**"Does this run?"** Use the demo host from this repo. No Claude required.

```bash
git clone https://github.com/Mikedan37/blaze-radar.git
cd blaze-radar
swift build -c release
export PATH="$PWD/.build/release:$PATH"

blaze-radar-demo-daemon &
```

**Terminal 1:**

```bash
cd /path/to/your-repo
blaze-radar-demo radar sync
blaze-radar-demo radar update --found "Token refresh is failing. Database is fine."
```

**Terminal 2:**

```bash
cd /path/to/your-repo
blaze-radar-demo radar sync
```

Terminal 2 should see Terminal 1's finding.

```bash
scripts/blaze-radar-sync-e2e.sh
```

The demo proves the board. `radar install` is what wires it into your agents day to day.

---

## Build on RadarCore

**"Can I embed this?"** This repo ships the engine.

| Piece | Purpose |
|-------|---------|
| **RadarCore** | Presence, findings, sync, collisions |
| **Demo CLI + daemon** | Local try-it host |
| **docs/** | Host and storage wiring |

```swift
import RadarCore

let service = AwarenessService()
let reg = try await service.register(
    workspacePath: "/path/to/repo",
    agentName: "agent-a",
    task: "fix auth",
    branch: nil,
    worktree: "/path/to/repo"
)
let _ = await service.sync(workspacePath: "/path/to/repo", registrationId: reg.id)
```

See [docs/AGENT_DAEMON_INTEGRATION.md](docs/AGENT_DAEMON_INTEGRATION.md). ProjectBlaze is one production host; it is not required.

```bash
swift test
```

---

## Where data lives

| What | Where |
|------|--------|
| Shared board | `<repo>/.blaze/radar/` |
| Per-agent identity | `~/.blaze/radar/` |

Add `.blaze/` to `.gitignore`.

---

## License

MIT. See [LICENSE](LICENSE).
