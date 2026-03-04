# Verdict (post-roll arbitration)

**File:** `app/services/dungeon_master/steps/verdict.rb`
**Template:** `app/services/dungeon_master/templates/verdict.text.erb`
**Pipeline step name:** `verdict`

## Purpose

Post-roll arbitration. Takes the dice results (both player and NPC), the
mechanical evaluation summaries, and the character sheet, and determines
the factual mechanical outcome. Did the attack hit? How much damage? Did
the save succeed? What conditions apply?

The output is factual, not narrative. It produces structured **mutations**
that the app applies to the database.

## Input

| Field | Source |
|---|---|
| System prompt | `verdict.text.erb` bound with: full player character block, mechanical evaluation summaries text, combined roll results (player + NPC), pending consequences, formatted micro-contexts |
| User message | The player's intention (from PlayerInterpreter step) |

## Output (JSON)

```json
{
  "outcome": "Factual summary of what happened mechanically",
  "reasoning": "How rolls were evaluated",
  "mutations": {
    "player": {
      "hp_change": -5,
      "conditions_add": ["prone"],
      "conditions_remove": [],
      "position": "in the sacred lake"
    },
    "npcs": [
      {
        "name": "Goblin A",
        "hp_change": -8,
        "conditions_add": [],
        "conditions_remove": [],
        "defeated": false,
        "attitude_change": null
      }
    ],
    "items_consumed": ["Potion of Cure Light Wounds"],
    "spells_used": ["Magic Missile"],
    "travel": {
      "hours_traveled": 10,
      "distance_covered": "approximately 40 miles on horseback along road",
      "new_location": "approaching the village outskirts"
    }
  }
}
```

The `travel` field is present when the action involves movement or travel.
It is `null` when no meaningful movement occurs.

## App-side post-processing

The `mutations` hash is applied by `DungeonMaster::Mutations#apply_mutations`:

- **Player HP**: clamped between negative constitution (death threshold)
  and `max_hp`
- **NPC HP**: clamped between 0 and `max_hp`
- **NPC attitude changes**: validated against `CreatureSheet::ATTITUDES`
  before persisting
- **Travel**: flows through to the Context Update step where it drives
  `traversal_context.current_location` updates
- **Conditions, items, spells**: logged but not yet mechanically enforced
  (future enhancement)

The `outcome` text is forwarded as the `narrate_seed` to the Stagehand
(output orchestration) step.

## Design rationale

Separating verdict from narration ensures the mechanical outcome is
determined objectively before the narrative is written. The mutations
structure is intentionally explicit (HP changes, not "takes damage") so
the app can apply them without interpreting natural language.

See [Design Philosophy](../design_philosophy.md) (Correctness over speed)
and [Decision 5: Verdict before narration](../pipeline_steps.md).
