# Step 8a: Micro Context Update

**File:** `app/services/dungeon_master/steps/context_update.rb`
**Template:** `app/services/dungeon_master/templates/micro_context_update.text.erb`
**Pipeline step name:** `micro_context_update`

## Purpose

Updates the micro-context JSONB fields on the Adventure model
(`traversal_context`, `combat_context`, `social_context`,
`exploration_context`, `rest_context`, `inventory_context`) to reflect
what just happened.

One AI call is made **per affected context**, all running in parallel
(mirroring the beacon pattern). Each call receives only the single
context it is responsible for updating, keeping the model focused and
avoiding cross-context interference. Unaffected contexts are not sent
at all — they are left unchanged in the DB.

`scene_summary` is produced by the highest-priority affected domain
(combat > social > traversal > exploration > rest > inventory).

Receives the factual outcome summary (`what_happened`) and mutations,
NOT the narrative text. This decouples context accuracy from narrative
style.

## Input

| Field | Source |
|---|---|
| System prompt | `micro_context_update.text.erb` bound with: the target `field` name, the current context JSON for that field, the factual outcome (`what_happened`), mutations JSON, canonical HP (if any), time result (if any), and a `primary` flag indicating whether this call should also produce `scene_summary` |
| User message | "Update the \<field\> context based on the above." |

## Output (JSON)

Only the relevant contexts appear in the output:

```json
{
  "traversal_context": {
    "current_location": "Sacred Lake shore",
    "terrain": "shallow water",
    "nearby_npcs": ["Village Elder"],
    "exits": ["north path", "lake center"]
  },
  "combat_context": {
    "active": true,
    "round": 3,
    "participants": [
      { "name": "Goblin A", "hp": 4, "conditions": [], "position": "10ft north" }
    ]
  },
  "social_context": {
    "npcs_present": [
      { "name": "Village Elder", "attitude": "unfriendly", "notes": "angry about sacred lake" }
    ]
  },
  "new_creatures": ["Water Elemental"],
  "scene_summary": "Fighting goblins at the Sacred Lake shore.",
  "reasoning": "Combat continues, traversal updated to lake, social tension with Elder"
}
```

## Scene summary

The context update step also produces a `scene_summary`, a single
concise sentence (under 15 words) describing the player's current
situation. Persisted on the `Adventure` model and shown in the UI.

## Context field schemas

**Traversal:** `current_location`, `destination`, `terrain`, `weather`,
`time_of_day`, `nearby_npcs`, `points_of_interest`, `exits`

**Combat:** `active`, `round`, `current_turn`, `turn_order`,
`participants` (name, hp, conditions, position), `terrain_notes`,
`active_effects`

**Social:** `scene`, `npcs_present` (name, role, attitude, notes),
`conversation_state`, `stakes`, `persuasion_progress`

**Exploration:** `searched_areas`, `discovered_items`, `discovered_secrets`,
`knowledge_checks_attempted`, `active_detection`, `pending_investigations`

**Rest:** `resting`, `hours_completed`, `total_hours_needed`, `watch_order`,
`interruptions`, `spells_prepared`, `hp_recovered`, `rest_complete`

**Inventory:** `recently_acquired`, `recently_used`,
`pending_identifications`, `equipped_changes`,
`notable_consumables_remaining`

## App-side post-processing

- Each non-empty context updates the corresponding Adventure JSONB field
- `scene_summary` updates the Adventure `scene_summary` column
- If `new_creatures` is present, the app performs a **bestiary lookup**
  for each name via `handle_new_creatures`. Matching `BestiaryEntry`
  records produce `CreatureSheet` instances with deterministically rolled
  HP.

## Design rationale

Micro-contexts are the pipeline's short-term memory. Every AI call
(sanitize excepted) receives them as context. Keeping them accurate is
critical. By having a dedicated step for context updates (rather than
asking each step to update context as a side effect), we ensure updates
happen exactly once, after all mechanics are resolved.

See [Decision 18: Selective context updates](../pipeline_steps.md) and
[Decision 29: Context updates receive factual outcomes](../pipeline_steps.md).
