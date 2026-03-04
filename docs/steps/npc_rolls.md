# App-side: NPC Roll Resolution

**File:** `app/services/dungeon_master/mutations.rb` (`resolve_npc_actions`)

## Purpose

Rolls dice for NPC actions deterministically. This is **not** an AI step —
it's pure application logic using `rand(1..20)`.

## Input

The merged `npc_actions` array from the MechanicalEvaluation step.

## Logic

For each NPC action:
1. Roll d20
2. Add the NPC's modifier (from the evaluation)
3. Compare against the player's AC (from the character sheet)
4. Produce a textual result: `"Goblin A attack -> rolled 14 + 3 = 17 vs AC 15: HIT"`

## Output

A text block of all NPC roll results, which feeds into the Ruling step.

## Player Roll Submission

When the pipeline returns `{ action: :awaiting_rolls }`, the UI presents
the player with the required rolls. The player submits their results,
which re-enter the pipeline through `DungeonMasterService#process_roll_result`.

This calls `Pipeline#run_rolls`, which:
1. Restores the intent and merged evaluation data from the persisted
   `roll_request` message metadata
2. Feeds everything into the Resolution Flow

## Design rationale

Having the app roll for NPCs ensures consistency and prevents the AI from
fudging results. The rolls use the modifiers specified by the mechanical
evaluation (which referenced actual creature stat blocks), keeping the
resolution grounded in real numbers.

See [Design Philosophy — Mechanical honesty](../design_philosophy.md#6-mechanical-honesty)
and [Decision 3: App-side NPC roll resolution](../pipeline_steps.md#3-app-side-npc-roll-resolution).
