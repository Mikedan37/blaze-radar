# Radar Dynamics: Control Theory for Parallel Agents

> **Thesis:** AI coding doesn't need a boss. It needs **state awareness**.
>
> Radar is not a multi-agent coordination platform. It is a **feedback layer** that changes the dynamics of parallel work — reducing repeated trajectories through state space without reducing useful system energy.

This document explains the control-theory framing behind Blaze Radar: what problem it solves, what it deliberately does *not* solve, how to evaluate whether it works, and where the hard problems move next.

For operational setup, see the [README](../README.md). For trial protocols and the full harness, see [BENCHMARK.md](BENCHMARK.md) and [AgentCLI scripts](https://github.com/Mikedan37/AgentCLI/tree/main/scripts).

---

## 1. The wrong model

The naive assumption when adding more agents:

```
more agents → need more coordination
```

That assumption produces a familiar stack:

```
planner
  ↓
task assignment
  ↓
ownership
  ↓
locks
  ↓
approval
```

This is middle management recreated for LLMs. It optimizes for **conflict avoidance** and **accountability theater**, not for **useful progress**. Agents become cautious. Throughput drops. Everyone attends standups. Humanity already maxed that skill tree.

Radar rejects this model entirely. The docs state it plainly:

- *"The board stays dumb; workers stay smart."*
- *"Radar does not lock files."*
- *"Make parallel agent work observable — not coordinate agents."*

The product is not managing agents. It is **changing the dynamics of the system**.

---

## 2. The correct model: state feedback

The Radar argument:

```
more agents → need more state feedback
```

The environment should tell each agent:

| Signal | Why it matters |
|--------|----------------|
| Where energy has already been spent | Avoid re-walking solved paths |
| What facts are known | Build on prior discoveries |
| What attempts failed | Enable informed exploration, not blind retry |
| What partial solutions exist | Compose instead of restart |

Then let intelligence decide. No planner assigns work. No lock blocks motion. No approval gate slows the loop.

Radar implements this as a **shared phase plane** — a whiteboard per git repository where each agent posts:

- **Task** — declared intent (what vector they're pursuing)
- **Notes** — discoveries, failures, partial fixes (state history)
- **Presence** — heartbeat via `sync` (who is active, how recently)

Hooks surface the board before edits. They **never block**. Culture (`CLAUDE.md`) instructs agents to sync, read, note, and respond to overlap warnings. The control loop is **advisory**, not authoritarian.

---

## 3. Control theory framing

### 3.1 State variable

Define the system's distance from resolution:

```
x(t) = distance from resolved system state
```

**Resolved** means: the bug is fixed, the feature ships, the investigation converges — not "every agent is in a separate directory."

The goal is fast convergence of `x(t) → 0` with **minimal heat loss** (wasted agent-minutes on redundant work).

### 3.2 Bad oscillation

Without state feedback, parallel agents exhibit under-damped behavior:

```
agent finds bug
  ↓
knowledge lost (no shared state)
  ↓
another agent restarts same investigation
  ↓
knowledge lost again
  ↓
system crosses the same states repeatedly
```

This is **oscillation**: the system traverses the same region of state space multiple times. It looks like progress (commits, stdout, file edits) but dissipates energy as heat — duplicate investigations, abandoned work, merge repair, conflicting patches.

### 3.3 What Radar adds

Radar injects **state feedback** into the loop:

```
(current board + history) → next action
```

Each `blaze radar sync` is a sample of the shared state. Each `blaze radar note` writes history into the phase plane. Collision warnings flag potential trajectory overlap. The agent's LLM is the controller — Radar is the sensor network.

### 3.4 Damping regimes

Map classical damping to multi-agent behavior:

| Regime | Multi-agent behavior | Radar stance |
|--------|---------------------|--------------|
| **Under-damped** (ζ < 1) | Thrashing: duplicate work, merge fights, rediscovery | What Radar targets |
| **Critical** (ζ ≈ 1) | Fast convergence, minimal overshoot, high throughput | Design goal |
| **Over-damped** (ζ > 1) | Slow, cautious, sync-heavy, deferential | What Radar avoids |

**Critical damping** in this context means:

> Fast convergence to a **stable solution trajectory** — not a territorial split.

Agents don't need lanes. They need **phase alignment**: complementary effort vectors that compound rather than collide.

---

## 4. Phase space: the core product insight

Human team metaphors ("ownership," "handoffs," "standups") break down for parallel LLM workers. Phase space is cleaner.

### 4.1 Position vs velocity

**Proximity in workspace ≠ collision.**

Two agents editing files in `src/auth/` is not automatically bad. Five agents on an auth outage can be optimal — if their vectors are aligned:

```
agent-01: traces root cause
agent-02: fixes backend
agent-03: fixes frontend
agent-04: writes regression tests
agent-05: validates deploy
```

That is not a split by territory. Everyone is on auth. The energy vectors are aligned. Efficient chaos.

What matters is **velocity through explored space** — whether an agent's next action traverses *new* state or retraces steps another agent already took.

### 4.2 The four quadrants

| Position | Velocity | Verdict |
|----------|----------|---------|
| Same area | New vector | ✅ Swarm — complementary angles on one problem |
| Different area | New vector | ✅ Parallel — independent progress |
| Same area | Same old vector | ❌ Oscillation — duplicate trajectory |
| Different area | Useless vector | ❌ Noise — wasted energy off the critical path |

Radar's overlap warnings are a **coarse sensor** for "same area + possibly same vector." They cannot distinguish swarm from collision automatically. **Notes** are what convert overlap into alignment:

> agent-01 notes: *"root cause is token refresh, not DB"*
>
> agent-02 reads note → changes vector → patches refresh logic instead of re-investigating DB

Without the note, same-area overlap looks like collision. With the note, it becomes compounding.

### 4.3 Exploration vs oscillation

Error is useful. Failed attempts are data. The system should not eliminate exploration — it should eliminate **uninformed repetition**.

| Scenario | Verdict |
|----------|---------|
| Agent tries a *different* auth fix after another agent's fix failed | ✅ Exploration |
| Agent tries the *same* failed auth fix because it didn't know | ❌ Oscillation |

Radar preserves exploration while attacking oscillation. The board records what was tried and what was learned. The next agent can branch intelligently instead of restarting blindly.

---

## 5. What Radar fixes (and what it doesn't)

### 5.1 Fixes

| Problem | Mechanism |
|---------|-----------|
| Duplicate investigations | Notes + sync deltas surface prior findings |
| Blind retries of failed paths | Failed attempts recorded as state history |
| Agents working in ignorance | Board visible before edits (hooks + contract) |
| Merge surprise | Early overlap warnings + declared tasks |
| Knowledge evaporation at session end | Notes persist in BlazeDB after `done` |

### 5.2 Does not fix

| Problem | Why not | Actual solution |
|---------|---------|-----------------|
| File-level write conflicts | No locks by design | Git worktrees + branches |
| Bad agent decisions | Board is advisory | Better models, prompts, culture |
| Merge conflicts | No merge logic | Git merge/rebase by human or agent |
| Task assignment | No planner | Agent intelligence + declared tasks |
| Guaranteeing agents read the board | No enforcement | Hooks + contract + trial evidence |

Radar makes work **observable**. It does not make agents **obedient**. That boundary is intentional.

---

## 6. System energy and heat loss

Useful framing for evaluation:

```
System energy  = total agent effort (agent-minutes, commits, tool calls)
Useful work    = effort that advances x(t) toward zero
Heat loss      = effort that retraces already-explored state
```

### 6.1 Bad Radar win (fear, not damping)

```
No Radar:  100 commits, 30 duplicate paths
Radar:      20 commits,  0 duplicate paths
```

Throughput collapsed. Agents became cautious. You invented corporate process — over-damping. Zero oscillation, zero velocity.

### 6.2 Good Radar win (same energy, less heat)

```
No Radar:  100 units effort → 60 useful, 40 repeated
Radar:     100 units effort → 85 useful, 15 repeated
```

Same system energy. Less heat loss. That is critical damping: oscillation reduced without killing motion.

### 6.3 Coordination score (trial scorer)

The trial scorer in `scripts/lib/score_trial_v2.py` encodes this intuition:

```
coordination_score = (useful_outputs + leverage − duplicate_work − merge_cost) / agent_minutes
```

Key signals:

| Signal | Meaning | Scoring |
|--------|---------|---------|
| `duplicate_investigations` | Same topic, multiple agents, no compounding | Penalized |
| `compounding_events` | Agent references prior board findings | Credited (Radar arm) |
| `complementary_changes` | Agents build on same files/areas differently | Credited |
| `territory_spread` | How many distinct areas each agent touched | **Diagnostic only** |

Territory spread is explicitly not the goal. Clustering on one area with complementary vectors scores well. Three agents independently "investigating auth timeout" with no compounding scores badly.

Compounding detection looks for language like:

- *"reused prior discovery"*
- *"from the board"*
- *"already found"*
- *"read the board before starting"*

Separation signals (*"out of my scope"*, *"leaving this to"*) are tracked but **not credited** — avoiding territory is not the product win; informed work is.

---

## 7. Radar as a control system (block diagram)

```
┌─────────────────────────────────────────────────────────────┐
│                     Shared Phase Plane                       │
│  (Radar board: tasks, notes, presence, overlap warnings)    │
└────────────▲───────────────────────────────▲────────────────┘
             │ write state                   │ read state
             │ (note, sync, task)            │ (sync, hooks)
     ┌───────┴───────┐               ┌───────┴───────┐
     │   Agent A     │               │   Agent B     │
     │  (controller) │               │  (controller) │
     └───────┬───────┘               └───────┬───────┘
             │ edits                           │ edits
             └──────────────┬──────────────────┘
                            ▼
                    ┌───────────────┐
                    │  Codebase /   │
                    │  Git state    │
                    └───────────────┘
```

**Sensor:** Radar board (what is known, who is active, where overlap exists)

**Actuators:** Agent edits, commits, notes (intelligence decides)

**Controller:** LLM + contract culture (not Radar daemon)

**Setpoint:** Resolved system state (bug fixed, feature shipped)

**Disturbance:** Parallel agents, incomplete information, session boundaries

Radar is deliberately **not** in the actuator path. Hooks surface stderr warnings; they do not block writes. This keeps the system on the left side of critical — feedback without friction.

---

## 8. Trial evaluation criteria

When running Radar vs no-Radar trials, the question is:

> Does adding feedback reduce oscillation **without** reducing system energy?

### 8.1 Pass conditions

| Metric | Pass | Fail |
|--------|------|------|
| Throughput | Same or higher (commits, useful diffs, agent-minutes productive) | Significantly lower |
| Duplicate trajectories | Lower (`duplicate_investigations`, abandoned work) | Same or higher |
| Leverage | Higher (`compounding_events`, prior context utilization) | Flat or lower |
| Merge cost | Same or lower | Higher (conflicts from ignorance) |
| Agent caution | Agents still explore new vectors | Agents defer, scope-shrink, sync-loop |

### 8.2 What to watch in transcripts

**Good signs:**

- Agent reads board, references another agent's note, changes approach
- Multiple agents on same area with different roles (trace / fix / test)
- Failed attempt noted → next agent tries *different* approach informed by failure
- Overlap warning → agent reads notes → continues with adjusted vector

**Bad signs:**

- Agent syncs constantly, produces little output
- Agent sees overlap → abandons all work in area (over-damping)
- Agent ignores board, repeats investigation visible in another agent's notes
- Agent claims awareness without running `blaze radar sync` (vibes, not state)

### 8.3 Harness boundary

The trial harness must **not** become a second coordinator. If Cursor/orchestrator tells agents what others are doing mid-run, you measure `Claude + harness + Radar` vs `Claude + harness` — three steering wheels. Radar's job in the Radar arm; nobody's in the no-Radar arm.

---

## 9. The next hard problem: feedback selection

As the board grows, **context retrieval becomes the new controller problem.**

Radar today surfaces:

- Active agents and tasks
- Recent notes (NEW deltas on sync)
- Overlap and related-area warnings
- Room history on first sync

This works at small scale. At larger scale, the question shifts from *"is there feedback?"* to *"what feedback does this agent need right now?"*

| Failure mode | Analog | Symptom |
|--------------|--------|---------|
| Too little feedback | Under-damped | Oscillation returns — agents miss relevant notes |
| Too much feedback | Over-damped | Agent reads entire board, slows down, loses momentum |
| Wrong feedback | Instability | Agent acts on stale or irrelevant note, goes off-vector |

The ranking/filtering problem:

```
given: agent task + current file + board history
return: minimal sufficient context for next action
```

This is not solved by Radar v1. The board is intentionally dumb — full dump, no ranking, no embeddings, no assignment. Future work might include:

- Relevance filtering (task overlap, file overlap, recency)
- Note summarization at scale
- Failed-attempt indexing ("don't retry these paths")
- Structured state (not just free-text notes)

But the design constraint remains: **sensor improvements, not actuator control.** Better feedback selection; still no boss.

---

## 10. Relationship to other ProjectBlaze control loops

Radar is one feedback layer. Other parts of ProjectBlaze use similar dynamics language:

| System | Control loop | See |
|--------|-------------|-----|
| **Radar** | Parallel agent state awareness | [RadarDynamics.md](docs/RadarDynamics.md), [BENCHMARK.md](docs/BENCHMARK.md) |
| **Risk Engine** | ARS → behavioral safety modes | [AgentCLI RiskModel](https://github.com/Mikedan37/AgentCLI/blob/main/Docs/RiskModel.md) |
| **Failure Memory** | Prior failures → plan constraints | [AgentCLI FailureMemory](https://github.com/Mikedan37/AgentCLI/blob/main/Docs/FailureMemory.md) |
| **Execution Guard** | Per-workspace serialization | AgentDaemon `WorkspaceLock` |

The Risk Engine's hysteresis band (block at 60, unlock at 75) is explicit anti-oscillation design — prevent flapping between blocked and unblocked near the threshold. Same philosophy: change dynamics, don't add a human in the loop.

Radar operates at a different layer: **between agents**, not **within one agent's safety envelope**.

---

## 11. Design principles (summary)

1. **State awareness, not management.** Observe; don't assign.
2. **Feedback, not friction.** Warn; don't block.
3. **Phase alignment, not territory.** Same area + new vector is fine.
4. **Exploration, not oscillation.** Failed attempts are data; blind retries are waste.
5. **Same energy, less heat.** Success = throughput preserved, duplication reduced.
6. **Dumb board, smart workers.** Intelligence decides; Radar informs.
7. **Notes are the product.** Overlap warnings are hints; notes are state history.

---

## 12. Elevator pitch

**Wrong:** "Multi-agent coordination platform with task assignment and ownership."

**Right:** "Shared phase plane for parallel coding agents. Tells them where energy was spent, what's known, what failed — so they compound instead of collide."

**One line:** Proximity in workspace ≠ collision. What matters is velocity through explored space.

---

## Appendix: glossary

| Term | Definition |
|------|------------|
| **Phase plane** | Shared state space (board) where agent position (task/area) and velocity (next action) are observable |
| **Oscillation** | Repeated traversal of already-explored state without compounding |
| **Exploration** | New trajectory informed by (or orthogonal to) prior attempts |
| **Heat loss** | Agent-minutes spent on redundant work |
| **Compounding** | Agent B's work builds on Agent A's recorded findings |
| **Swarm** | Multiple agents on same area with aligned, complementary vectors |
| **Over-damping** | Excessive caution — low oscillation, low throughput |
| **Critical damping** | Fast convergence to useful trajectory without killing system energy |
