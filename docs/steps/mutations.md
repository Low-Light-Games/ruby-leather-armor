# App-side: Mutation Application

**File:** `app/services/dungeon_master/mutations.rb`

## Purpose

Handles all non-AI state changes between the Verdict and Narrate steps.

## `apply_mutations(mutations)`

Applies the structured mutations hash from the Verdict step:

- **Player HP changes**: applied to the player's `CreatureSheet`,
  clamped between negative constitution (death) and max HP
- **NPC HP changes**: applied to matching `CreatureSheet` records,
  clamped between 0 and max HP
- **NPC attitude changes**: validated against the
  `CreatureSheet::ATTITUDES` whitelist before persisting

## `handle_new_creatures(creature_names)`

Called by the Micro Context Update step when `new_creatures` is present:

1. Checks if a `CreatureSheet` already exists for this adventure
2. Looks up the name in the `BestiaryEntry` table (case-insensitive)
3. If found, creates a `CreatureSheet` with deterministically rolled HP
   using the bestiary entry's `hp_formula` (e.g. "2d8+4")
4. If not found, logs a warning (the creature appears in narrative but
   has no stat block)

## Design rationale

Mutations are applied by code, not AI. The AI decides *what happened*;
the app ensures the numbers are correct and bounded.

See [Design Philosophy](../design_philosophy.md) (Mechanical honesty,
AI for judgment code for certainty).
