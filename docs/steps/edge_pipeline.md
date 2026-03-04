# Edge Pipeline (alternative mode)

**File:** `app/services/dungeon_master/edge_pipeline.rb`
**Template:** `app/services/dungeon_master/templates/edge_pipeline.text.erb`
**Pipeline step name:** `edge_pipeline`

## Purpose

A monolithic single-call alternative to the budget pipeline. Handles
sanitization, intent, capability checks, mechanics (with internally
simulated dice rolls), mutations, narration, and context updates all
in one response.

Activated when `DmConfig` `pipeline_mode` is set to `"edge"`.

## Trade-offs vs. budget pipeline

| | Budget Pipeline | Edge Pipeline |
|---|---|---|
| Latency | 5-15s (10+ round-trips) | 2-5s (1 round-trip) |
| Per-step model control | Yes | No |
| Per-step token budgets | Yes | No |
| Roll requests to player | Yes | No (AI simulates internally) |
| Debugging granularity | Per-step logs | Single opaque log |
| Cost tuning | Cheap steps use nano models | One model for everything |

## Input

| Field | Source |
|---|---|
| System prompt | `edge_pipeline.text.erb` bound with: full character block, creature stats, story block, micro-contexts, pacing instructions, directed play instructions, dm_query_mode flag |
| User message | Raw player input |

## Output (JSON)

```json
{
  "rejected": false,
  "rejection_reason": null,
  "narrative": "The DM's response",
  "adventure_complete": false,
  "mutations": {},
  "context_updates": {},
  "scene_summary": "Current situation",
  "story_summary_update": null,
  "reasoning": "Internal reasoning"
}
```

In DM query mode, replaces `narrative` with `dm_answer`.

## App-side post-processing

- If `rejected`: return `{ action: :rejected }`
- If `dm_answer`: return `{ action: :dm_query }`
- Otherwise: apply mutations, persist context updates, persist scene
  summary, optionally update story summary, return
  `{ action: :narrated }`

## Design rationale

Edge mode exists for scenarios where the budget pipeline's latency or
complexity is unacceptable. It is a deliberate trade-off: less accurate,
less debuggable, less configurable, but faster and simpler. The
`pipeline_mode` toggle lets the admin switch between modes without code
changes.

See [Design Philosophy](../design_philosophy.md) (Coexistence over
migration, When in doubt add a toggle).
