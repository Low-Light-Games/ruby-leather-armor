# Step 7: Narrate

**File:** `app/services/dungeon_master/steps/narrate.rb`
**Template:** `app/services/dungeon_master/templates/narrate.text.erb`
**Pipeline step name:** `narrate`

## Purpose

The player-facing creative step. Takes the mechanical outcome (or nothing,
for non-mechanical actions) and produces the DM's narrative response.
This is the text the player actually reads.

## Input

| Field | Source |
|---|---|
| System prompt | `narrate.text.erb` bound with: story title, story context (hook + atmosphere + DM brief), story summary, formatted micro-contexts, mechanical outcome text (from Verdict, or nil), player action and intent (for non-mechanical path), pacing instructions, directed play instructions |
| User message | The outcome text (mechanical path), or the player's action text (non-mechanical path) |

## Output (JSON)

```json
{
  "narrative": "The DM's vivid narrative prose",
  "adventure_complete": false
}
```

## Key fields explained

- **`narrative`**: the text shown to the player. Written in DM voice,
  respecting pacing settings.
- **`adventure_complete`**: when `true`, the service persists an
  additional `adventure_complete` system message. This signals the UI
  that the adventure has concluded.

## Pacing control

The narrate template receives `pacing_text` which varies based on
DmConfig settings:
- **Verbose off**: instructs the DM to keep responses to 1-2 paragraphs
  within the configured word range (default: min 80, max 150 words)
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
determine hit/miss, or decide outcomes -- that was done in Verdict.

See [Design Philosophy - Immersion preservation](../design_philosophy.md)
and [Decision 5: Verdict before narration](../pipeline_steps.md).
