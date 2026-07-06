# Radar Benchmark Harness

Multi-agent trials that measure whether Radar reduces **repeated trajectories** without reducing **throughput**.

**Design framing:** [RadarDynamics.md](RadarDynamics.md)

---

## Where the harness lives

The full benchmark stack ships in **[AgentCLI](https://github.com/Mikedan37/AgentCLI)** (ProjectBlaze production host):

| Piece | Path |
|-------|------|
| Harness runner | [scripts/run-trial.sh](https://github.com/Mikedan37/AgentCLI/blob/main/scripts/run-trial.sh) |
| Facts collector | [scripts/collect-trial.sh](https://github.com/Mikedan37/AgentCLI/blob/main/scripts/collect-trial.sh) |
| Scorer v2 | [scripts/lib/score_trial_v2.py](https://github.com/Mikedan37/AgentCLI/blob/main/scripts/lib/score_trial_v2.py) |
| Protocol | [scripts/radar-trial-1-protocol.md](https://github.com/Mikedan37/AgentCLI/blob/main/scripts/radar-trial-1-protocol.md) |
| Overview | [scripts/RadarBenchmark.md](https://github.com/Mikedan37/AgentCLI/blob/main/scripts/RadarBenchmark.md) |

This repo (**blaze-radar**) ships **RadarCore** — the board engine trials measure. AgentCLI ships the host CLI, hooks, and benchmark harness that drive Claude Code agents against a real repo.

---

## Experiment shape

```
Claude Code × N + Radar   vs   Claude Code × N, no Radar
```

Held constant: repo, base SHA, model, duration, prompt pack, merge order.  
Variable: coordination layer (board, sync, notes, overlap warnings).

---

## Pass / fail (from RadarDynamics)

| Good Radar win | Bad Radar win |
|----------------|---------------|
| Same agent-minutes, fewer duplicate investigations | Fewer commits, zero duplicates (over-damping / fear) |
| Higher compounding (agents reuse board notes) | Agents sync constantly, produce little |
| Merge cost flat or down | Throughput collapsed |

**Coordination score** (scorer v2):

```
(useful_outputs + leverage − duplicate_work − merge_cost) / agent_minutes
```

Key signals:

- `duplicate_investigations` — penalized
- `compounding_events` / prior context utilization — credited (Radar arm)
- `complementary_changes` — credited (swarm on same area OK)
- `territory_spread` — diagnostic only, not the goal

---

## Quick start (AgentCLI)

```bash
git clone https://github.com/Mikedan37/AgentCLI.git
cd AgentCLI

# Prerequisites: blaze + daemon, claude, target repo (default ~/SeekerWebsite)
./scripts/run-trial.sh --mode radar --trial trial-002-radar
./scripts/run-trial.sh --mode no-radar --trial trial-002-no-radar
./scripts/score-trial.sh --trial trial-002 \
  --report ~/radar-benchmarks/trial-002/benchmark-report.md
```

See [RadarBenchmark.md](https://github.com/Mikedan37/AgentCLI/blob/main/scripts/RadarBenchmark.md) for full options, prompt packs, and harness boundaries.

---

## Harness boundary

During a trial, the orchestrator **must not** tell agents what others are doing. That is Radar's job in the Radar arm — and nobody's in the no-Radar arm. Mid-run task routing invalidates the experiment.
