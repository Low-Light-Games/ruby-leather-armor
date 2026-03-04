# Step 2: Intent

**File:** `app/services/dungeon_master/steps/intent.rb`
**Template:** `app/services/dungeon_master/templates/intent.text.erb`
**Pipeline step name:** `intent`

## Purpose

Pure intent interpretation. Restates what the player is trying to do in
clear, unambiguous language. Does NOT evaluate rules, determine required
rolls, classify domains, or identify affected contexts — those
responsibilities belong to the InterpretationDispatcher.

## Input

| Field | Source |
|---|---|
| System prompt | `intent.text.erb` (static, no dynamic bindings) |
| User message | Sanitized player input (from Sanitize) |

## Output

A string: the clear restatement of the player's intention. The Intent
step returns `parsed["intention"]` directly (not a hash).

```json
{
  "intention": "Clear, unambiguous restatement of what the player wants to do",
  "reasoning": "Brief explanation of how you interpreted the input"
}
```

## Relationship with Sequencer

When `action_queue` is enabled, the Sequencer step runs before Intent
and splits compound player inputs into an ordered queue of action texts.
Intent then runs **once per action** in the queue, interpreting each
action text individually.

For single actions (the majority), this is transparent — Intent runs
exactly once, as before. Intent's prompt and output are completely
unchanged by the Sequencer feature.

## Design rationale

Intent is deliberately minimal. By separating "what does the player want?"
from "how does that affect the game?", the Intent step produces a clean,
unambiguous seed that domain-specific dispatchers can evaluate
independently. Keeping the prompt static (no context injection) makes it
fast and cheap.

See [Design Philosophy — Structured decomposition over model reasoning](../design_philosophy.md#3-structured-decomposition-over-model-reasoning)
and [Decision 25: InterpretationDispatcher](../pipeline_steps.md#25-interpretationdispatcher-parallel-per-domain-interpretation).
