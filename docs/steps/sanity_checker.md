# Step 4b: SanityChecker

**File:** `app/services/dungeon_master/steps/sanity_checker.rb`
**Templates:**
- `templates/sanity_checker.text.erb` (capability check, AI mode only)
- `templates/sanity_checker_world.text.erb` (world consistency check)

**Pipeline step names:** `sanity_checker` (capability), `sanity_checker_world` (world consistency)

## Purpose

Two sub-checks under one umbrella, validating player actions from
different angles:

**A) Capability Check** — validates that the player actually possesses the
spells, feats, or items they are attempting to use. Only runs on the
mechanics path (when `needs_mechanics` is true), in parallel with
MechanicalEvaluation.

**B) World Consistency Check** — validates that the entities, targets, or
objects the player references actually exist in the current game world
state. Runs ALWAYS — via the full gate on the mechanics path, or as a
standalone call on the non-mechanics path.

## Sub-task A: Capability Check

Controlled by `DmConfig` `guardrail_mode`:

**Code mode** (`"code"`, default): deterministic fuzzy-match against the
character sheet. Regex patterns extract spell/feat/item references from
the intention text and check them against the sheet's known names.
No AI call — zero cost, sub-millisecond execution.

**AI mode** (`"ai"`): sends the full character block and intention to an
AI model for holistic validation. More nuanced (can catch implicit
references, prerequisite chains) but costs an API call.

### Output

```json
{
  "allowed": true,
  "reason": null
}
```

When `allowed` is `false`, the pipeline returns `{ action: :rejected }`
with the capability check's `reason`.

## Sub-task B: World Consistency Check

AI-only step — no code mode. Receives the broadest context of any step
in the pipeline:

- **All non-empty micro-contexts** (combat, traversal, social,
  exploration, rest, inventory) — the source of truth for what is
  currently in the scene
- **Scene summary** — current scene description
- **Scene history** — last N scene snapshots for continuity (configurable
  via `scene_history_depth`, default 10)
- **Story NPCs** — provided as reference with a caveat that they may or
  may not be present in the current scene

Creature sheet names are deliberately NOT included. A creature sheet
persists after the creature is defeated/fled — its existence says nothing
about scene presence. The micro-contexts (`combat_context` participants,
`social_context` NPCs) and `scene_summary` already capture what is
actually present.

### Output

```json
{
  "consistent": true,
  "referenced_entities": ["goblin", "merchant"],
  "reason": null
}
```

When `consistent` is `false`, the pipeline returns `{ action: :rejected }`
with the world check's `reason`.

### Model requirements

This is the hardest judgment call in the pipeline. The AI must
cross-reference a player's declared action against the full world state,
detect subtle inconsistencies, and avoid both false positives (blocking
creative play) and false negatives (letting players conjure entities out
of thin air).

Unlike other steps where we decompose the problem to make cheap models
viable, this step receives the broadest context and demands genuine
reasoning. **Recommended model: gpt-4o-mini or better** (gpt-4.1-mini,
o3-mini, gpt-5-mini). The DmConfig UI displays a warning when a budget
model is selected for this step.

## Parallel execution

On the mechanics path, all three checks (MechanicalEvaluation +
Capability Check + World Consistency Check) run concurrently in
`run_full_gate`. If either sanity check fails, the mechanical evaluation
work is discarded.

On the non-mechanics path, the world check runs standalone — there's
nothing to parallelize it with since `time_keeper` has side effects
(advances the game clock) and can't run speculatively.

## Error handling

Both sub-checks fail open on errors — they return `{ allowed: true }` or
`{ consistent: true }` respectively. This prevents a validation system
error from blocking the player. Errors are logged for admin review.

## Design rationale

The original CapabilityGuardrail only checked player capabilities and
only ran on the mechanics path. This left a gap: players could reference
non-existent creatures, NPCs, or objects on the non-mechanics path, and
the pipeline would happily process the action. The World Consistency
Check closes this gap.

Running it in parallel with MechanicalEvaluation means zero additional
latency on the happy path (the overwhelmingly common case — valid
actions). The occasional wasted mech eval work on rejection is a
deliberate tradeoff.

See [Design Philosophy — AI for judgment](../design_philosophy.md) and
[Pipeline Steps — Decision 26](../pipeline_steps.md).
