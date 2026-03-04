# PlayerInterpreter (pure intent interpretation)

**File:** `app/services/dungeon_master/steps/player_interpreter.rb`
**Template:** `app/services/dungeon_master/templates/player_interpreter.text.erb`
**Pipeline step name:** `player_interpreter`

## Purpose

Pure intent interpretation. Restates what the player is trying to do in
clear, unambiguous language. Does NOT evaluate rules, determine required
rolls, classify domains, or identify affected contexts — those
responsibilities belong to the Beacon step.

## Input

| Field | Source |
|---|---|
| System prompt | `player_interpreter.text.erb` (static, no dynamic bindings) |
| User message | Sanitized player input (from Sanitize) |

## Output

A string: the clear restatement of the player's intention. The
PlayerInterpreter step returns `parsed["intention"]` directly (not a hash).

```json
{
  "intention": "Clear, unambiguous restatement of what the player wants to do",
  "reasoning": "Brief explanation of how you interpreted the input"
}
```

## Relationship with Sequencer

When `action_queue` is enabled, the Sequencer step runs before
PlayerInterpreter and splits compound player inputs into an ordered queue
of action texts. PlayerInterpreter then runs **once per action** in the
queue, interpreting each action text individually.

For single actions (the majority), this is transparent —
PlayerInterpreter runs exactly once. Its prompt and output are completely
unchanged by the Sequencer feature.

## Design rationale

PlayerInterpreter is deliberately minimal. By separating "what does the
player want?" from "how does that affect the game?", it produces a clean,
unambiguous seed that domain-specific beacons can evaluate
independently. Keeping the prompt static (no context injection) makes it
fast and cheap.

The name "PlayerInterpreter" clarifies that this step interprets the
*player's* words, not game rules (see naming convention in
`docs/design_philosophy.md`).

See [Design Philosophy — Structured decomposition over model reasoning](../design_philosophy.md#3-structured-decomposition-over-model-reasoning)
and [Decision 25: Beacon](../pipeline_steps.md#25-beacon-parallel-per-domain-interpretation).
