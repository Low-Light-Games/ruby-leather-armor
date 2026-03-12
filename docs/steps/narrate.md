# Step 7: Narrate

**File:** `app/services/dungeon_master/steps/narrate.rb`
**Template:** `app/services/dungeon_master/templates/narrate.text.erb`
**Pipeline step name:** `narrate`

## Purpose

The player-facing creative step. Takes the factual outcome (from Mechanic
or Momentum, via the loop) and produces the DM's narrative response.
This is the text the player actually reads.

## Input

| Field | Source |
|---|---|
| System prompt | `narrate.text.erb` bound with: story title, story context (hook + atmosphere + DM brief), story summary, formatted micro-contexts, time context, `what_happened` (from loop's `verdict_outcome`), outcome (narrate_seed), journey data (from loop), encounter scene/new elements/creatures (from loop), pacing instructions, directed play instructions |
| User message | The outcome text (narrate_seed) |

### Loop data read

| Key | Used as |
|---|---|
| `verdict_outcome` | `@what_happened` in template — factual outcome from Mechanic or Momentum. When `run_accumulated_output_phase` runs (after roll/initiative resumption with multiple queued actions), this is built from `combined_seed` rather than the loop's per-action verdict. |
| `journey_data` | `@journey_data` — structured travel info (origin, destination, distance, terrain) |
| `encounter_scene` | `@encounter_scene` — Harbinger's encounter narrative |
| `encounter_new_elements` | `@encounter_new_elements` — world elements introduced by encounter |
| `encounter_creatures` | Drives `@encounter_has_creatures` boolean |

## Output (JSON)

```json
{
  "narrative": "The DM's vivid narrative prose"
}
```

## Pacing control

The narrate template receives `pacing_text` which varies based on
DmConfig settings:
- **Verbose off**: instructs the DM to keep responses to 1-2 paragraphs
  within the configured word range (default: min 40, max 120 words)
- **Verbose on**: no word limits, the DM may write longer, richer
  responses

## Directed play

When the adventure has `directed_dm` enabled, the template includes
additional instructions that guide the DM to steer the narrative
toward the story's premise and hooks, ensuring the adventure progresses
even with a passive player.

## Design rationale

Narration is deliberately isolated from mechanical resolution. The model
receives a factual outcome ("you hit for 8 damage, goblin has 4 HP
remaining") and transforms it into prose. It does not adjudicate rules,
determine hit/miss, or decide outcomes — that was done in Mechanic
(mechanical path) or Momentum (non-mechanical path).

The `what_happened` field is always populated on the loop before Narrate
runs, so the "purely narrative moment" fallback is no longer needed.

See [Design Philosophy - Immersion preservation](../design_philosophy.md)
and [Decision 5: Mechanic before narration](../pipeline_steps.md).
