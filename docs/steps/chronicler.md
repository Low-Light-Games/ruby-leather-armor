# Step 5b: Chronicler

**File:** `app/services/dungeon_master/steps/chronicler.rb`
**Template:** `app/services/dungeon_master/templates/chronicler.text.erb`
**Pipeline step name:** `chronicler`

## Purpose

Plot state management and spoiler gating. Evaluates whether the player's
action reveals story clues, triggers NPC reactions, or reaches milestones.
Produces a "DM Brief" that guides the Narrate step on what to describe,
hint at, or avoid.

Runs conditionally when the adventure has structured story data
(StoryNpc, StoryClue records). A deterministic heuristic fallback
(`heuristic_chronicler`) handles clue discovery when the AI Chronicler is
skipped.

## Input

| Field | Source |
|---|---|
| System prompt | `chronicler.text.erb` bound with: enriched premise, current plot state (discovered/attempted clues, met NPCs, milestones), player's action and outcome, undiscovered clues with discovery conditions, available NPCs at current location |
| User message | "Evaluate plot state for this action." |

## Output (JSON)

```json
{
  "clues_to_reveal": [{ "id": 1, "title": "..." }],
  "clues_attempted": [{ "id": 2, "title": "...", "reason": "why it failed" }],
  "npc_reactions": { "NPC Name": "brief reaction instruction" },
  "atmosphere_notes": "optional atmospheric detail (only when chronicler_tone_direction is enabled)",
  "milestones_reached": [{ "title": "...", "consequence": "..." }],
  "narration_guidance": "DM Brief for the narrator",
  "adventure_complete": false,
  "plot_state_updates": {
    "discovered_clues_add": [1],
    "attempted_clues_add": [2],
    "npc_met_add": [3],
    "custom_facts_add": ["free-text fact"]
  },
  "reasoning": "Evaluation logic"
}
```

## Key fields

- **`adventure_complete`**: boolean. When `true`, signals that all key
  milestones have been reached and the story has naturally concluded.
  Written to the loop; read by Stagehand to set the adventure-complete
  flag on the response. (Moved here from Narrate — Chronicler has full
  plot context and is better positioned to make this determination.)
- **`atmosphere_notes`**: only present when `chronicler_tone_direction`
  is enabled in DmConfig. When disabled, the Chronicler focuses purely on
  what to reveal, hint, or hide — no tone/atmosphere guidance.

## App-side post-processing

- `plot_state_updates` are merged into the adventure's `plot_state` JSONB
- `adventure_complete` is written to the loop via `batch_update!`
- The `narration_guidance` string becomes the `dm_brief` parameter passed
  to the Narrate step

## Tone toggle (`chronicler_tone_direction`)

When `DmConfig.chronicler_tone_direction` is `false` (default), the
Chronicler template omits `atmosphere_notes` and tone-related instructions
from `narration_guidance`. The DM's natural voice is preserved. When
enabled, the Chronicler provides atmosphere/mood direction alongside
plot guidance.

## Design rationale

The Chronicler separates plot awareness from narration. The narrator
never sees the full premise or unrevealed secrets. It only receives the
`dm_brief`, which tells it what to describe without spoiling what it
should not know. This prevents the narration model from accidentally
leaking future plot points.

See [Design Philosophy](../design_philosophy.md) (Immersion preservation,
Prompt isolation).
