# CoreResolver

**File:** `app/services/dungeon_master/core_resolver.rb`

## Purpose

The inner pipeline: resolves a single player action from beacon
through time_keeper. Extracted from `Pipeline` so the outer orchestrator
(`orchestrate_actions`) can loop over queued actions without duplicating
resolution logic.

CoreResolver is a module included by `Pipeline`. It calls step methods
(beacon, mechanics gate, verdict, time_keeper) that are already mixed
into Pipeline via their own step modules.

## Interface

### `resolve(intention, category)`

Full resolution: beacon → full gate (mech eval + world check + cap check)
→ [verdict + mutations + time_keeper]. On the non-mechanics path: beacon
→ world check → time_keeper. Returns a result hash with `:status`:

| Status | Meaning |
|---|---|
| `:resolved` | Action fully resolved. `narrate_seed` and `mutations` available. |
| `:awaiting_rolls` | Rolls needed. `intent` and `merged` available for roll pause. |
| `:encounter` | Harbinger triggered an encounter. `narrate_seed` has the encounter narrative. |
| `:rejected` | SanityChecker rejected the action (capability or world consistency). `reason` available. |

### `finish_resolution(intent, merged, roll_results)`

Post-roll completion: verdict → mutations → time_keeper. Called when the
player submits roll results. Returns the same result hash structure as
`resolve`.

## Result hash shape

```ruby
{
  status:       :resolved | :awaiting_rolls | :encounter | :rejected,
  intent:       { intention:, affected_contexts:, ... },
  narrate_seed: "Factual outcome text" | nil,
  mutations:    { player: ..., npcs: ... } | nil,
  merged:       { player_rolls:, npc_actions:, ... },  # only for :awaiting_rolls
  time_result:  { hours_elapsed:, ... } | nil,
  reason:       "Rejection reason",                     # only for :rejected
}
```

## How it's used

The `orchestrate_actions` method in Pipeline calls `resolve` once per
action in the Sequencer's queue:

```ruby
actions.each do |action_text|
  intention = run_player_interpreter(action_text)
  result = resolve(intention, category)
  # handle :awaiting_rolls, :encounter, :resolved, :rejected
end
```

Roll resumption calls `finish_resolution` then continues the queue if
`remaining_actions` exist in the metadata.

## Design rationale

**Why a module, not a class?** CoreResolver calls step methods
(`run_beacon`, `run_full_gate`, `run_verdict`, etc.) that are
mixed into Pipeline. A separate class would need all those dependencies
injected. A module shares Pipeline's instance variables naturally.

**Why extracted at all?** Before action queuing, the resolution logic
lived inline in `run_action_flow` and `run_resolution_flow`. The queue
loop needs to call this logic N times. Extracting it avoids duplication
and makes the loop body trivial.
