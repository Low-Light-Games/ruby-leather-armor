# Momentum (non-mechanical outcome determination)

**File:** `app/services/dungeon_master/steps/momentum.rb`
**Template:** `app/services/dungeon_master/templates/momentum.text.erb`
**Pipeline step name:** `momentum`

## Purpose

Determines the factual outcome of player actions that require no dice rolls
or skill checks. Runs on the **non-mechanical path** after TimeKeeper. Where
Mechanic resolves "did the attack hit?", Momentum resolves "what happened
when the player talked to the innkeeper?" or "how far did the party travel?"

Also identifies which context domains were affected by the action, merging
its assessment with the beacons' initial analysis.

## When it runs

Momentum runs when `intent[:needs_mechanics]` is `false` — the action has
no rolls, no saves, no checks. Examples:

- Conversing with an NPC
- Traveling to a known destination
- Searching a room (when no Perception check is needed)
- Setting up camp
- Examining an object

**Exception:** Momentum is skipped when `intent[:expand_scene]` is true. In
that case, the Social Expansion step replaces Momentum for significant NPC
interactions (transactions, negotiations, confrontations), creating an
immersive scene that pauses for player input instead of auto-resolving.

## Input

| Field | Source |
|---|---|
| System prompt | `momentum.text.erb` bound with: player intention, time data (hours elapsed, source), journey data (if travel), formatted micro-contexts, available context domain names |
| User message | The player's intention |

## Output (JSON)

```json
{
  "outcome": "Factual summary of what happened",
  "affected_contexts": ["traversal", "rest", "exploration"],
  "reasoning": "Brief explanation",
  "mutations": {}
}
```

## Loop data written

| Key | Value |
|---|---|
| `verdict_outcome` | The `outcome` string (truncated to 500 chars) — same key as Mechanic, so downstream steps read from one place |
| `affected_contexts` | Merged array: beacon-assessed domains ∪ AI-assessed domains |

## Context domain merging

Momentum merges two sources of affected-context information:

1. **Beacon assessment** — stored on the loop by the Beacon step
2. **AI assessment** — Momentum's own analysis of which domains changed

The union of both is written back to the loop. This matters because
beacons run before the action resolves, while Momentum runs after —
it can catch indirect effects (e.g., a journey affects `traversal` but
also `rest` via fatigue and `exploration` via new surroundings).

## Design rationale

Before Momentum, non-mechanical actions had no step determining what
factually happened. The Narrate step received a nil outcome and had to
both decide and describe. This violated the pipeline's separation of
concerns (facts vs. prose).

Momentum fills the same role as Mechanic but for the non-mechanical path,
ensuring `verdict_outcome` is always populated on the loop before Narrate
runs.

## Model recommendation

**Recommended:** gpt-4.1-mini, gpt-4o-mini, gpt-5-nano

Mid-tier model. The task requires moderate judgment (what changed, which
domains are affected) but not deep mechanical reasoning.

**Token budget:** 500 (default).
