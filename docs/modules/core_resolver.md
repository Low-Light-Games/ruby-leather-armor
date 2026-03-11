# CoreResolver

**File:** `app/services/dungeon_master/core_resolver.rb`

## Purpose

The inner pipeline: resolves a single player action from beacon
through time_keeper. Extracted from `Pipeline` so the outer orchestrator
(`orchestrate_actions`) can loop over queued actions without duplicating
resolution logic.

CoreResolver is a module included by `Pipeline`. It calls step methods
(beacon, mechanics gate, mechanic, momentum, time_keeper) that are
already mixed into Pipeline via their own step modules.

## Interface

### `resolve(intention, category)`

Full resolution with two paths:

**Mechanical path:** beacon → full gate (mech eval + world check + cap check)
→ mechanic + mutations → time_keeper. Returns `:resolved` with
`narrate_seed` from the mechanic outcome.

**Non-mechanical path:** beacon → world check → time_keeper → momentum.
Returns `:resolved` with `narrate_seed` from the momentum outcome.
`verdict_outcome` is always written to the loop by either Mechanic or
Momentum, so downstream steps have a single read location.

| Status | Meaning |
|---|---|
| `:resolved` | Action fully resolved. `narrate_seed` and `mutations` available. |
| `:awaiting_rolls` | Rolls needed. `intent` and `merged` available for roll pause. |
| `:awaiting_initiative` | Combat starting, waiting for player initiative roll. |
| `:encounter` | Harbinger triggered an encounter. `narrate_seed` from loop's `verdict_outcome`. |
| `:rejected` | SanityChecker rejected the action (capability or world consistency). `reason` available. |

### `finish_resolution(intent, merged, roll_results)`

Post-roll completion: mechanic → mutations → time_keeper. Called when the
player submits roll results. Returns the same result hash structure as
`resolve`.

### `maybe_warmaster_for_encounter(intent, time_result, mutations:)`

Called when Harbinger triggers an encounter (Path A). Encounter data is
read exclusively from the loop (set by Harbinger during TimeKeeper).
Returns `:awaiting_initiative` or `:encounter`.

### `resolve_unified(intention, category)`

Unified evaluation path: single AI call replaces beacons + mech eval +
roll qualifier. Sanity checks still run independently. Same two-path
structure (mechanical/non-mechanical) as `resolve`.

## Result hash shape

```ruby
{
  status:       :resolved | :awaiting_rolls | :encounter | :rejected | :awaiting_initiative,
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
(`run_beacon`, `run_full_gate`, `run_mechanic`, etc.) that are
mixed into Pipeline. A separate class would need all those dependencies
injected. A module shares Pipeline's instance variables naturally.

**Why extracted at all?** Before action queuing, the resolution logic
lived inline in `run_action_flow` and `run_resolution_flow`. The queue
loop needs to call this logic N times. Extracting it avoids duplication
and makes the loop body trivial.
