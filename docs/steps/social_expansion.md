# Social Expansion (social scene expansion)

**File:** `app/services/dungeon_master/core_resolver.rb` (method: `resolve_social_scene`)
**Template:** `app/services/dungeon_master/templates/social_expansion.text.erb`
**Pipeline step name:** `social_expansion`

## Purpose

Expands significant social interactions into immersive NPC scenes that pause
for player input. Analogous to how the Encounter Expander creates vivid
combat scenes — the Social Expander creates the opening of an NPC interaction
and ends at the first natural decision point, giving the player agency to
respond however they choose.

Without this step, all non-mechanical social interactions (renting a room,
negotiating with a merchant, asking an NPC for information) are auto-resolved
by Momentum: "you rented the room" with no player input. Social Expansion
adds a third resolution mode between mechanical (dice rolls) and auto-resolve
(Momentum).

## When it runs

Social Expansion runs when ALL of the following are true:

- `intent[:needs_mechanics]` is `false` (non-mechanical path)
- `intent[:expand_scene]` is `true` (flagged by the Social Beacon)
- World consistency check has passed

When it runs, it **replaces** TimeKeeper + Momentum. TimeKeeper is
intentionally skipped — no time passes until the interaction resolves in a
subsequent pipeline run.

### Examples of actions that trigger expansion

- Renting a room at an inn
- Buying equipment from a merchant
- Asking a bartender for information
- Negotiating a price or service
- Confronting an NPC

### Examples that do NOT trigger expansion

- Casual greetings ("I say hello to the guard")
- Simple observations ("I look at the merchant's wares")
- Continuing an ongoing social interaction (re-expansion guard prevents this)

## Input

| Field | Source |
|---|---|
| System prompt | `social_expansion.text.erb` bound with: player intention, current location name, social micro-context, full character block, known NPC names, social beacon's domain interpretation |
| User message | The player's intention string |

## Output (JSON)

```json
{
  "scene": "The innkeeper, a stout woman with flour-dusted hands...",
  "npc_name": "innkeeper",
  "npc_attitude": "indifferent",
  "new_elements": [],
  "reasoning": "Brief explanation (1 sentence)"
}
```

### NPC attitudes

Uses the Pathfinder 1e NPC attitude scale: `hostile`, `unfriendly`,
`indifferent`, `friendly`, `helpful`. The attitude is written to the
adventure loop for potential downstream mechanics reference.

## Loop data written

| Key | Value |
|---|---|
| `social_scene` | The expanded scene text (truncated to 1000 chars) |
| `verdict_outcome` | Same scene text (truncated to 500 chars) — consistent with Mechanic/Momentum write location |
| `social_npc_name` | NPC name (if present) |
| `social_npc_attitude` | NPC attitude (if present) |
| `social_new_elements` | Array of new world elements introduced (if any) |

## Queue behavior

Returns `{ status: :social_scene }`, which causes the Pipeline to:

1. Update the loop status to `"social_scene"`
2. Accumulate the result
3. Break the action queue (like `:encounter`)
4. Log the interruption with reason `"social_scene"`
5. Run the output phase (narrate + context updates) for all accumulated results

The player's response enters a fresh `run_prompt` call. The social context
(updated by ContextUpdate in the output phase) provides continuity.

## Re-expansion guard

The Social Beacon is instructed to NOT flag `expand_scene: true` when the
`social_context` already contains an active NPC interaction. This prevents
infinite scene expansion loops. The player's response resolves through
Momentum (auto-resolve) or the mechanical path (if they attempt something
requiring a skill check like Diplomacy or Intimidate).

## Files

| File | Purpose |
|------|---------|
| `app/services/dungeon_master/core_resolver.rb` | `resolve_social_scene` method |
| `app/services/dungeon_master/templates/social_expansion.text.erb` | AI prompt template |
| `app/services/dungeon_master/steps/beacon.rb` | `expand_scene` extraction and propagation |
| `app/services/dungeon_master/templates/beacon/_social.text.erb` | Social beacon `expand_scene` guidance |

## Design rationale

Before Social Expansion, the pipeline had a binary choice for non-mechanical
actions: auto-resolve via Momentum or reject via SanityChecker. Social
interactions — which in tabletop RPGs are rich, multi-turn exchanges with
NPC personality, negotiation, and player agency — were flattened into single
factual outcomes with no player input.

The Encounter Expander already proved the pattern: take a bare trigger,
expand it into an immersive scene, pause for the player. Social Expansion
applies the same pattern to NPC interactions.

The step lives in CoreResolver (not a separate step module) because it
occupies the same architectural slot as Momentum — it's an alternative
resolution for the non-mechanical path, not an additional step in the
sequence.

## Model recommendation

**Recommended:** gpt-4.1-mini, gpt-4o-mini, gpt-5-nano

Mid-tier model. The task requires moderate creativity (NPC personality,
atmospheric scene) and Pathfinder 1e knowledge (pricing, attitudes), but
not deep mechanical reasoning.

**Token budget:** 500 (default).
