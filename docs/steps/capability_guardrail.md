# Step 4b: CapabilityGuardrail

**File:** `app/services/dungeon_master/steps/capability_guardrail.rb`
**Template:** `app/services/dungeon_master/templates/capability_guardrail.text.erb` (AI mode only)
**Pipeline step name:** `capability_guardrail`

## Purpose

Validates that the player actually possesses the spells, feats, or items
they are attempting to use. Runs in parallel with MechanicalEvaluation.

## Modes

Controlled by `DmConfig` `guardrail_mode`:

**Code mode** (`"code"`, default): deterministic fuzzy-match against the
character sheet. Regex patterns extract spell/feat/item references from
the intention text and check them against the sheet's known names.
No AI call — zero cost, sub-millisecond execution.

**AI mode** (`"ai"`): sends the full character block and intention to an
AI model for holistic validation. More nuanced (can catch implicit
references, prerequisite chains) but costs an API call.

## Output

```json
{
  "allowed": true,
  "reason": null
}
```

When `allowed` is `false`, the pipeline returns `{ action: :rejected }`
with the guardrail's `reason`.

## Error handling

Both modes fail open on errors — they return `{ allowed: true }`. This
prevents a validation system error from blocking the player. Errors are
logged for admin review.

## Design rationale

Capability validation was previously embedded in the mechanical evaluation
prompt, which frequently overlooked it. A dedicated guardrail ensures
validation never competes with other concerns for the model's attention.
Running it in parallel with MechanicalEvaluation means zero additional
latency.

See [Design Philosophy — Honor system](../design_philosophy.md#2-honor-system)
and [Decision 26: CapabilityGuardrail](../pipeline_steps.md#26-capabilityguardrail-character-validation).
