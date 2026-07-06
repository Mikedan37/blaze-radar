# Radar Benchmark

Multi-agent trials that measure whether Radar reduces **repeated trajectories** without reducing **throughput**.

**This repo does not ship the harness.** The public benchmark lives in its own project:

👉 **[blaze-radar-benchmark](https://github.com/Mikedan37/blaze-radar-benchmark)**

| Doc | Contents |
|-----|----------|
| [README](https://github.com/Mikedan37/blaze-radar-benchmark/blob/main/README.md) | Purpose, quick start, layout |
| [RadarDynamics.md](https://github.com/Mikedan37/blaze-radar-benchmark/blob/main/docs/RadarDynamics.md) | Control theory framing, pass/fail criteria |
| [protocol/trial-1-protocol.md](https://github.com/Mikedan37/blaze-radar-benchmark/blob/main/protocol/trial-1-protocol.md) | Frozen experiment contract |

---

## Experiment shape

```
Claude Code × N + Radar   vs   Claude Code × N, no Radar
```

**Good win:** same energy, less heat loss (fewer duplicate paths, more compounding).  
**Bad win:** fewer commits, zero duplicates — over-damping.

---

## Quick start

```bash
git clone https://github.com/Mikedan37/blaze-radar-benchmark.git
cd blaze-radar-benchmark

# Build Radar demo host first (see blaze-radar README)
./harness/run-trial.sh --mode radar --trial trial-002-radar --repo ~/YourRepo
./harness/score-trial.sh --trial trial-002
```

See the [benchmark repo](https://github.com/Mikedan37/blaze-radar-benchmark) for full harness, scorer, and prompt packs.
