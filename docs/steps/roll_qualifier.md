# Step 4c: RollQualifier

**File:** `app/services/dungeon_master/steps/roll_qualifier.rb`
**Template:** `app/services/dungeon_master/templates/roll_qualifier.text.erb`
**Pipeline step name:** `roll_qualifier`

## Purpose

Evaluates situational context to determine:

1. **Situational modifiers** — circumstance bonuses/penalties from
   environmental factors (flanking, high ground, cover, surprise, terrain
   conditions, lighting, etc.)
2. **Take 10 / Take 20 eligibility** — whether the character is free from
   immediate danger, distraction, and time pressure

This step runs **after each MechanicalEvaluation domain iteration** that
produces `player_rolls`. If a domain evaluation returns no rolls, the
qualifier is skipped for that domain.

## Why a separate step

MechanicalEvaluation is deliberately scoped to a single domain with minimal
context to keep prompts lean and focused on rules adjudication. Situational
assessment requires broader cross-domain awareness:

- Is the character in combat or under threat from another domain?
- Is there implicit time pressure from the story or quest?
- Does failure have consequences (disqualifying Take 20)?
- Are there positional advantages from terrain or allies?

Separating this into its own step keeps MechanicalEvaluation focused on
"what rolls are needed" while RollQualifier answers "under what conditions."

## Context scope toggle

The `roll_qualifier_scope` setting in DmConfig controls how much context is
provided to the qualifier. Options:

| Value | Context provided | Trade-off |
|---|---|---|
| `all` | All 6 micro-contexts + scene_summary | Thorough, heavy token cost |
| `domain` | Domain's own micro-context + scene_summary | Lean prompt, usually sufficient (**default**) |
| `dynamic` | Contexts selected by MechanicalEvaluation via `qualifier_context_hints` | Adaptive per evaluation |
| `social_traversal` | Social + Traversal contexts + scene_summary | Best for out-of-combat |
| `traversal_combat` | Traversal + Combat contexts + scene_summary | Best near combat |
| `scene` | Scene summary only | Minimal tokens |

### Dynamic mode

When `roll_qualifier_scope` is `"dynamic"`, MechanicalEvaluation includes a
`qualifier_context_hints` array in its JSON output (e.g.,
`["combat", "traversal"]`). The RollQualifier reads these hints and pulls
only the specified contexts. Falls back to `"domain"` if hints are empty.

## Input

| Field | Source |
|---|---|
| System prompt | `roll_qualifier.text.erb` bound with: domain name, mechanical_summary from preceding evaluation, context block (per scope toggle), scene_summary, rolls to qualify as JSON |
| User message | The player's intention (from Intent step) |

## Output (JSON)

```json
{
  "qualifications": [
    {
      "skill": "Perception",
      "take_10_eligible": true,
      "take_20_eligible": false,
      "take_10_value": 15,
      "take_20_value": null,
      "situational_modifiers": [
        { "source": "well-lit campfire", "bonus": 2, "type": "circumstance" }
      ],
      "reasoning": "Character is at a safe camp, no threats."
    }
  ],
  "reasoning": "Overall situational assessment"
}
```

## App-side post-processing

The qualifier annotates each roll in the evaluation's `player_rolls` with:

- `take_10_eligible` / `take_20_eligible` — booleans
- `take_10_value` / `take_20_value` — pre-computed totals (modifier + 10/20)
- `situational_modifiers` — array of applicable bonuses

These annotations are carried through `merge_mechanical_evaluations` into
the `roll_request` message metadata, where the frontend uses them to offer
Take 10/Take 20 buttons alongside the standard d20 roll.

## Auto-success filter

After all evaluations are merged, a code-only
`filter_auto_success_rolls!` strips rolls guaranteed to succeed:

- DC <= 0 (impossible to fail regardless of roll type)
- Skill checks where the modifier guarantees success (modifier + 1 >= DC)
- Skill checks where Take 10 auto-succeeds (take_10_value >= DC)

Saves and attack rolls are only auto-filtered at DC <= 0 (natural 1 is
auto-fail for these in Pathfinder 1e).

## Frontend integration

The chat UI uses RollQualifier annotations to present three options per roll:

- **Roll (+N)** — standard d20 roll with the resolved modifier and formula
- **Take 10 (= X)** — instantly resolves with modifier + 10, shown when eligible
- **Take 20 (= X)** — instantly resolves with modifier + 20, shown when eligible

## Design rationale

The RollQualifier always runs as an AI step when rolls exist — there is no
code short-circuit beyond the "no rolls" skip. This is intentional because:

- Even in combat, situational modifiers (flanking, cover, surprise) require
  AI judgment about the specific tactical situation.
- Take 10/20 eligibility depends on narrative context (implicit urgency,
  environmental threats) that cannot be reliably determined by code alone.

See [Decision 1: Sequential pipeline](../pipeline_steps.md) and
[Design Philosophy: AI for judgment, code for certainty](../design_philosophy.md).
