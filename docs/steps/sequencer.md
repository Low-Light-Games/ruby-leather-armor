# Sequencer

**File:** `app/services/dungeon_master/steps/sequencer.rb`
**Template:** `app/services/dungeon_master/templates/sequencer.text.erb`
**Pipeline step name:** `sequencer`

## Purpose

Detects compound player inputs that describe multiple sequential actions
and splits them into an ordered array of action texts. Runs before PlayerInterpreter
so each action gets its own PlayerInterpreter interpretation and resolution cycle.

Single actions (the vast majority) return a one-element array. The
pipeline loop body executes once — identical to the pre-Sequencer flow.

## When it runs

- After the gate (intake) and before PlayerInterpreter
- Skipped entirely when `DmConfig.action_queue` is `false`
- Errors fall back gracefully to `[original_input]` (single action)

## Input

- System prompt: static template (no dynamic locals)
- User message: the sanitized player input

## Output

```json
{
  "actions": ["rest for the night", "head to the village in the morning"],
  "reasoning": "The player describes two sequential actions separated by temporal conjunction."
}
```

Only `actions` is used; `reasoning` is for audit/debug.

## Splitting rules

The prompt instructs the model to split only on **temporal sequence** —
one action happening after another in time. It explicitly excludes:

- Simultaneous actions ("sneak past the guards and pick the lock")
- Combat round tactics ("dodge and counterattack")
- Cautious single tasks ("search for traps before opening")
- Maximum 3 actions per split

## Ordering rules

When splitting compound actions, the Sequencer applies **ordering rules**
to determine execution order:

1. **Immediate decisions** — actions that require an immediate response
   (e.g., combat reactions, time-sensitive choices) come first.
2. **Preparatory actions** — setup, buffs, or preparation (e.g., "I cast
   Mage Armor before entering") come before the main action they enable.
3. **Travel / consequential** — movement and travel actions follow
   preparatory ones; consequential actions (e.g., "then I search the room")
   come last.

This ordering ensures the pipeline resolves actions in a narratively
coherent sequence rather than arbitrary list order.

## Model selection

Fast, cheap model — same tier as PlayerInterpreter and Intake. The task is
classification + extraction, not reasoning. Budget: 200 tokens.

## Design rationale

**Why not regex?** Temporal conjunctions ("then", "after that", "once
done") seem parseable by pattern matching, but edge cases are unbounded.
"I then cast fireball" should not split. "I fire, then reload" is
ambiguous. See design_philosophy.md principle 1 (corollary on regex).

**Why not inside PlayerInterpreter?** PlayerInterpreter is a nano-model step focused on
restating what the player wants. Adding compound detection would bloat
its prompt and risk degrading its core task on cheap models. Separation
keeps both steps focused and independently testable.

**Why before PlayerInterpreter, not parallel?** Each action in the queue needs its
own PlayerInterpreter call. Running Sequencer in parallel with PlayerInterpreter would produce
a PlayerInterpreter output for the full compound input, which gets discarded for
compound actions — wasteful. Sequential ordering is cleaner.
