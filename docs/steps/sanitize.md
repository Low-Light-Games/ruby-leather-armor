# Step 1a: Sanitize

**File:** `app/services/dungeon_master/steps/triage.rb` (`run_sanitize`)
**Template:** `app/services/dungeon_master/templates/sanitize.text.erb`
**Pipeline step name:** `sanitize`

## Purpose

Security filter. Scores the player input for danger on a 0-100 scale.
Runs in parallel with Classify (no dependencies between them).

Danger categories: prompt injection, meta-gaming, rule manipulation,
DM behavior directives, out-of-character harassment.

## Input

| Field | Source |
|---|---|
| System prompt | `sanitize.text.erb` (static, no dynamic bindings) |
| User message | Raw player input (unmodified) |

## Output (JSON)

```json
{
  "danger_score": 0,
  "sanitized_input": "cleaned version of the player's input",
  "reason": "explanation of danger assessment, null if safe"
}
```

## App-side post-processing

- If `danger_score >= sanitization_threshold`: pipeline returns
  `{ action: :rejected }` immediately. No further AI calls are made.
- The `sanitized_input` (not the raw input) is forwarded to all
  subsequent steps.

## Design rationale

Sanitize is intentionally the cheapest, simplest step with a static
prompt (no dynamic context). It's a pure gatekeeper: fast to execute,
cheap to run, and its failure mode (rejecting safe input) is far less
damaging than letting malicious input through.

See [Design Philosophy — AI for judgment, code for certainty](../design_philosophy.md#1-ai-for-judgment-code-for-certainty)
and [Decision 24: Sanitize/Classify split](../pipeline_steps.md#24-sanitizeclassify-split-parallel-gate).
