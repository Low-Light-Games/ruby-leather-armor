# Step 1c: DM Query (fast path)

**File:** `app/services/dungeon_master/steps/dm_query.rb`
**Template:** `app/services/dungeon_master/templates/dm_query.text.erb`
**Pipeline step name:** `dm_query`

## Purpose

Answers out-of-character player questions ("What are my known spells?",
"How does grappling work?", "What can I see around me?") without
advancing the scene or triggering any mechanics.

This is a **fast path**: when Classify categorizes the input as `dm_query`,
the pipeline skips Intent, beacon, evaluation, verdict, narration, and
context updates entirely. The question goes in, an answer comes out,
nothing changes.

## Input

| Field | Source |
|---|---|
| System prompt | `dm_query.text.erb` bound with: story title, story summary, formatted micro-contexts, DM guidance text, spoiler guidance from Chronicler (if available) |
| User message | Sanitized player input (from Sanitize) |

## Output (JSON)

```json
{
  "answer": "The DM's answer to the player's question",
  "reasoning": "What informed the answer"
}
```

## App-side post-processing

- The `answer` is persisted as a `dm_query` message type (role: `dm`).
- No context is updated. No mutations are applied. No state changes.

## Design rationale

Many player messages are questions, not actions. Routing them through the
full pipeline would be wasteful and could cause unintended side effects
(context updates reflecting a non-event). The fast path keeps query
latency low and cost minimal.

See [Decision 9: DM Query fast path](../pipeline_steps.md#9-dm-query-fast-path).
