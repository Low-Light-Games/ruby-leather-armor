# Stagehand (code-only output orchestration)

**File:** `app/services/dungeon_master/steps/stagehand.rb`
**Pipeline step name:** (no AI call — no step name in logs)

## Purpose

Code-only routing step. Sits between the Mechanic/Momentum step and
the output phase (Narrate + ContextUpdate). No AI call.

Responsibilities:
1. Check if combat beacon signaled combat_started (Path B Warmaster gate)
2. Package outcome + DM brief into a narrative seed for Narrate
3. Package factual outcome + mutations into directives for ContextUpdate
4. Read `affected_contexts` from the loop (set by Momentum or Beacon),
   falling back to `intent[:affected_contexts]` when unavailable
5. Read `adventure_complete` from the loop (set by Chronicler)
6. Dispatch the output phase based on `narration_mode` config

## Loop data read

| Key | Purpose |
|---|---|
| `affected_contexts` | Merged context domains from Momentum/Beacon — passed to ContextUpdate |
| `adventure_complete` | Boolean set by Chronicler — signals adventure conclusion |

## narration_mode

- `"parallel"` (default): Narrate and ContextUpdate run concurrently in
  threads. Lower latency, but Narrate doesn't see fresh context.
- `"subjugated"`: ContextUpdate runs first, then Narrate. Higher latency,
  but Narrate can read the freshly updated contexts.

## Design rationale

This step exists as a routing layer to keep the pipeline's flow method
clean. By encapsulating the parallel-vs-sequential decision and the
data packaging in one place, the outer orchestrator (`orchestrate_actions`)
and the CoreResolver remain simple dispatchers.

The name "Stagehand" reflects its code-only nature — it coordinates
backstage without creative agency (see naming convention in
`docs/design_philosophy.md`).

See [Decision 27: Stagehand as code-only synthesis step](../pipeline_steps.md)
and [Decision 28: Narration mode toggle](../pipeline_steps.md).
