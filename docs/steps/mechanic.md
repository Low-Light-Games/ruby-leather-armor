# Mechanic (post-roll arbitration)

**File:** `app/services/dungeon_master/steps/mechanic.rb`
**Template:** `app/services/dungeon_master/templates/mechanic.text.erb`
**Pipeline step name:** `mechanic`

## Purpose

Post-roll arbitration. Takes the dice results (both player and NPC), the
mechanical evaluation summaries, and the character sheet, and determines
the factual mechanical outcome. Did the attack hit? How much damage? Did
the save succeed? What conditions apply?

The output is factual, not narrative. It produces structured **mutations**
that the app applies to the database. Writes `verdict_outcome` to the
adventure loop so downstream steps (Narrate, Stagehand) can read it.

## Input

| Field | Source |
|---|---|
| System prompt | `mechanic.text.erb` bound with: full player character block, mechanical evaluation summaries text, combined roll results (player + NPC), pending consequences, formatted micro-contexts |
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
    "spells_used": ["Magic Missile"]
  }
}
```

## Loop data written

| Key | Value |
|---|---|
| `verdict_outcome` | The `outcome` string (truncated to 500 chars) |

## App-side post-processing

The `mutations` hash is applied by `DungeonMaster::Mutations#apply_mutations`:

- **Player HP**: clamped between negative constitution (death threshold)
  and `max_hp`
- **NPC HP**: clamped between 0 and `max_hp`
- **NPC attitude changes**: validated against `CreatureSheet::ATTITUDES`
  before persisting
- **Conditions, items, spells**: logged but not yet mechanically enforced
  (future enhancement)

The `outcome` text is stored on the loop as `verdict_outcome` and read
by the Narrate step via the loop (not passed as a parameter).

## Design rationale

Separating mechanical arbitration from narration ensures the outcome is
determined objectively before the narrative is written. The mutations
structure is intentionally explicit (HP changes, not "takes damage") so
the app can apply them without interpreting natural language.

Previously named "Verdict" — renamed to "Mechanic" to better reflect its
role as mechanical-only arbitration, distinct from the new Momentum step
which handles non-mechanical outcomes.

See [Design Philosophy](../design_philosophy.md) (Correctness over speed)
and [Decision 5: Mechanic before narration](../pipeline_steps.md).
