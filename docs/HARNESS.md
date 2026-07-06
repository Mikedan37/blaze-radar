# Radar Harness

Control theory + measurement framework for parallel AI coding agents.

**Public repo:** [blaze-radar-harness](https://github.com/Mikedan37/blaze-radar-harness)

```
blaze-radar          →  state awareness layer
blaze-radar-harness  →  oscilloscope on multi-agent dynamics
```

| Doc | Contents |
|-----|----------|
| [README](https://github.com/Mikedan37/blaze-radar-harness/blob/main/README.md) | Purpose, metrics map, quick start |
| [RadarDynamics.md](https://github.com/Mikedan37/blaze-radar-harness/blob/main/docs/RadarDynamics.md) | Phase space, exploration vs oscillation, damping |
| [trial-1-protocol.md](https://github.com/Mikedan37/blaze-radar-harness/blob/main/protocol/trial-1-protocol.md) | Frozen experiment contract |

---

## What it measures

Not a leaderboard — instrumentation for system behavior:

| Domain | Signals |
|--------|---------|
| Oscillation | duplicate investigations, repeated paths |
| Energy | agent-minutes, useful output, throughput |
| Damping | prior context use, compounding, continuations |

**Good result:** same energy, less heat loss.  
**Bad result:** fewer commits, zero duplicates — over-damping.

---

## Quick start

```bash
git clone https://github.com/Mikedan37/blaze-radar-harness.git
cd blaze-radar-harness

./harness/run-trial.sh --mode radar --trial trial-002-radar --repo ~/YourRepo
./harness/score-trial.sh --trial trial-002
```

Build [blaze-radar](https://github.com/Mikedan37/blaze-radar) first (`blaze-radar-demo-daemon` + `blaze-radar-demo`).
