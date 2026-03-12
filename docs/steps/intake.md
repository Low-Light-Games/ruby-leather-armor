# Step 1: Intake

**File:** `app/services/dungeon_master/steps/triage.rb` (`run_intake`)
**Template:** `app/services/dungeon_master/templates/intake.text.erb`
**Pipeline step name:** `intake`

## Purpose

Security filter. Scores the player input for danger on a 0-100 scale.
Detects DM queries (questions about rules, inventory, etc.) and suggests
context domains that may need initialization for the player's intent.

Runs as a single call (no parallel gate). Replaces the former Sanitize +
Classify parallel pair.

## Input

| Field | Source |
|---|---|
| System prompt | `intake.text.erb` (static, no dynamic bindings) |
| User message | Raw player input (unmodified) |

## Output (JSON)

```json
{
  "danger_score": 0,
  "sanitized_input": "cleaned version of the player's input",
  "reason": "explanation of danger assessment, null if safe",
  "is_dm_query": false,
  "suggested_context": ["combat", "traversal"],
  "context_suggestion_reason": "why these domains were suggested, null if none"
}
```

## App-side post-processing

- If `danger_score >= danger_threshold`: pipeline returns
  `{ action: :rejected }` immediately. No further AI calls are made.
- If `is_dm_query == true`: pipeline branches to the DM Query fast path.
- The `sanitized_input` (not the raw input) is forwarded to all
  subsequent steps.
- When `suggested_context` is present and non-empty, an `ExperienceSuggestion`
  record is created for logging context gap suggestions.

## Design rationale

Intake is intentionally the cheapest, simplest step with a static
prompt (no dynamic context). It combines security scoring, dm_query
detection, and context gap suggestion in one call — a pure gatekeeper
that is fast to execute and cheap to run. Its failure mode (rejecting
safe input) is far less damaging than letting malicious input through.

See [Design Philosophy — AI for judgment, code for certainty](../design_philosophy.md#1-ai-for-judgment-code-for-certainty)
and [Decision 24: Sanitize/Classify merged into Intake](../pipeline_steps.md#24-sanitizeclassify-split-parallel-gate).
