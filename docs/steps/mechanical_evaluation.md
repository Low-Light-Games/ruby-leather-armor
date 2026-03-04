# Step 4a: MechanicalEvaluation

**File:** `app/services/dungeon_master/steps/mechanical_evaluation.rb`
**Template:** `app/services/dungeon_master/templates/mechanical_evaluation.text.erb`
**Pipeline step name:** `mechanical_evaluation`

## Purpose

The rules engine. Determines what dice rolls are needed, what NPC actions
occur, and what automatic consequences follow -- all within Pathfinder 1e
rules. Runs in parallel with CapabilityGuardrail.

Each domain receives **domain-specific instructions** loaded from partial
files (`templates/mechanical_evaluation/_combat.text.erb`,
`_traversal.text.erb`, etc.). These partials contain Pathfinder 1e rules
guidance relevant to that domain.

## The loop

This step runs **once per affected context** identified by the dispatchers.
The primary context is processed first, so subsequent evaluations can
reference its summary.

```
Iteration 1: MechanicalEvaluation for COMBAT
  -> "Player attacks Goblin A, provoking AoO from Goblin B"
  -> mechanical_summary: "[COMBAT] Player swings at Goblin A..."

Iteration 2: MechanicalEvaluation for TRAVERSAL
  -> receives previous summary: "[COMBAT] Player swings at Goblin A..."
  -> "Player also attempts to move 10 feet toward the door"
  -> mechanical_summary: "[TRAVERSAL] Player moves toward the door..."
```

## Input (per iteration)

| Field | Source |
|---|---|
| System prompt | `mechanical_evaluation.text.erb` bound with: domain name, domain-specific character block, micro-context for this domain, creature/NPC stat blocks, previous evaluation summaries, fetched rules text, domain-specific instruction partial |
| User message | The player's intention (from Intent step) |

## Output (JSON, per iteration)

```json
{
  "player_rolls": [
    { "type": "skill_check", "skill": "Swim", "dc": 10, "description": "Swim check to stay afloat" }
  ],
  "npc_actions": [
    { "actor": "Goblin A", "action": "attack", "target": "player", "modifier": 3 }
  ],
  "consequences": [
    { "target": "NPC Name", "effect": "attitude_shift", "from": "friendly", "to": "unfriendly", "reason": "explanation" }
  ],
  "mechanical_summary": "Brief mechanical summary of what happens in this domain",
  "reasoning": "Brief explanation of rules applied"
}
```

## App-side post-processing

After all iterations complete, results are **merged** by
`merge_mechanical_evaluations`:

```ruby
{
  player_rolls:          evaluations.flat_map { |e| e[:player_rolls] },
  npc_actions:           evaluations.flat_map { |e| e[:npc_actions] },
  consequences:          evaluations.flat_map { |e| e[:consequences] },
  mechanical_summaries:  evaluations.map { |e| "[#{e[:domain].upcase}] #{e[:mechanical_summary]}" }
}
```

If `player_rolls` is non-empty, the pipeline **pauses** and returns
`{ action: :awaiting_rolls }`. The merged data is persisted in the
`roll_request` message's metadata so the pipeline can resume later.

If no player rolls are needed (e.g. only NPC actions and consequences),
the pipeline proceeds directly to the Resolution Flow.

## Design rationale

The evaluation step is deliberately scoped to one domain per call. The
`player_rolls` / `npc_actions` split is also deliberate: player rolls are
resolved by the player (submitted via UI), while NPC rolls are resolved
deterministically by the app.

See [Decision 4: MechanicalEvaluation loop](../pipeline_steps.md) and
[Decision 21: Domain-specific instruction partials](../pipeline_steps.md).
