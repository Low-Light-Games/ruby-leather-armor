# Warmaster (Utility)

**Type**: Code utility (no AI call of its own, but may delegate to `creature_generation`)
**Location**: `app/services/dungeon_master/utilities/warmaster.rb`

## Purpose

Handles the full lifecycle of combat initialization: creature sheet creation,
initiative rolling, and `combat_context` population. Ensures that when combat
starts, the mechanical state is consistent before narration or further
resolution proceeds.

## Entry Paths

### Path A — Encounter Table (Harbinger-triggered)

Called by `CoreResolver#maybe_warmaster_for_encounter` when `TimeKeeper` /
`Harbinger` rolls an encounter with an `EncounterTableEntry`.

1. If the entry has a `creature_manifest`, creatures are spawned deterministically
   (bestiary lookup by ID, count, display name).
2. If no manifest, creature names are extracted from the entry description and
   spawned via fuzzy bestiary lookup + dynamic fallback.

### Path B — Narrative-originated combat

Called by `Stagehand#maybe_initialize_combat` when the combat beacon returns
`transition: "combat_started"` with a `combatants` list.

1. The combatant names are passed through fuzzy bestiary lookup.
2. Unmatched names go through the dynamic fallback chain (`ai` or `template`
   per `creature_creation_fallback` in DmConfig).

## Creature Resolution Chain

```
1. fuzzy_bestiary_match (singularize → exact LOWER match → ILIKE → id fallback)
2. dynamic_creature_sheet:
   a. "ai" mode  → creature_generation AI prompt → parse → CreatureSheet
   b. "template" → tier-scaled stat block from CREATURE_TEMPLATE hash
   c. "none"     → skip (creature not created)
```

## Initiative

- Warmaster rolls initiative for all spawned creatures (d20 + DEX mod + Improved Initiative feat if present).
- Returns `{ status: :awaiting_initiative, creature_data: [...] }` to pause the pipeline.
- The pipeline sends an `initiative_request` message to the player.
- If the player responds with an initiative roll, `finalize_combat!` is called.
- If the player ignores the prompt and sends a regular action, the service layer
  auto-rolls player initiative via `auto_roll_player_initiative` (d20 + DEX mod)
  and finalizes combat before processing the new action.

## combat_context Structure

```json
{
  "active": true,
  "round": 1,
  "participants": [
    { "name": "Goblin 1", "creature_sheet_id": 42, "initiative": 15, "type": "npc" },
    { "name": "Player", "initiative": 18, "type": "player" }
  ],
  "turn_order": ["Player", "Goblin 1"],
  "active_effects": []
}
```

## Guards

- `TimeKeeper#consult_harbinger_if_needed` skips Harbinger when `combat_active?`
  is true, preventing re-triggering during combat.
- `Stagehand#maybe_initialize_combat` checks `combat_context["active"]` to avoid
  re-initializing combat already in progress.
- The combat beacon partial displays active participant info when combat is active,
  preventing the AI from re-signaling `combat_started`.

## Configuration

| DmConfig key                  | Default    | Description                                       |
|-------------------------------|------------|---------------------------------------------------|
| `creature_creation_fallback`  | `"ai"`     | `"ai"`, `"template"`, or `"none"`                 |
| `creature_generation` (model) | (default)  | Model override for AI creature stat generation     |
| `creature_generation` (budget)| 600        | Token budget for creature generation calls          |
