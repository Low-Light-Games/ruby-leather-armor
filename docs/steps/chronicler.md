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
  "atmosphere_notes": "optional atmospheric detail",
  "milestones_reached": [{ "title": "...", "consequence": "..." }],
  "narration_guidance": "DM Brief for the narrator",
  "plot_state_updates": {
    "discovered_clues_add": [1],
    "attempted_clues_add": [2],
    "npc_met_add": [3],
    "custom_facts_add": ["free-text fact"]
  },
  "reasoning": "Evaluation logic"
}
```

## App-side post-processing

- `plot_state_updates` are merged into the adventure's `plot_state` JSONB
- The `narration_guidance` string becomes the `dm_brief` parameter passed
  to the Narrate step

## Design rationale

The Chronicler separates plot awareness from narration. The narrator
never sees the full premise or unrevealed secrets. It only receives the
`dm_brief`, which tells it what to describe without spoiling what it
should not know. This prevents the narration model from accidentally
leaking future plot points.

See [Design Philosophy](../design_philosophy.md) (Immersion preservation,
Prompt isolation).
