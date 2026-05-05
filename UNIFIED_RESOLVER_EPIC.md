# Unified Resolver Epic — toward a tool-calling GM

Plan doc for collapsing Sequencer + RollRequest + CombatRollRequest + Mechanic
(as AI step) into a single reasoning-model AI step (`Resolver`) that uses
tool calling for retrieval and emits a structured `ActionPlan` consumed by
deterministic downstream code. Intake remains as a cheap moderation gate.

This is a pre-launch redesign: no coexistence toggle, no incremental dual-path,
no migration of in-flight adventures (we are not yet live to migrate).

---

## Why now

Three converging forces:

1. **RollRequest is already a reasoning model with retrieval.** It's doing
   the hardest judgment in the pipeline. Asking it to also decide
   "is this one action or many?" and to emit branch-aware roll plans is
   a smaller cognitive load than what it shoulders today, not a larger one.

2. **The current split prevents coherent reasoning.** "I stealth in and
   attack" gets cut by Sequencer into two unrelated actions, then
   RollRequest evaluates each independently with no knowledge of the other.
   `progressive_continuity` mode is itself a workaround for this blindness.
   A unified call sees the whole intent and emits a coherent plan with
   branch semantics in one shot.

3. **Pre-launch cost discipline.** Each AI step in the pipeline is a
   separate dollar line item. Going to launch with N tunable knobs that
   each affect cost in poorly-understood ways is operationally fragile.
   Collapsing to "one big call, well-instrumented" gives us one cost
   surface to watch.

---

## Final pipeline shape

```
Player input
  │
  ├─ Intake (gpt-4.1-nano, ~1s)
  │     ↑ cheap moderation gate; bails on danger_score ≥ threshold
  │     ↑ no retrieval, no reasoning model, no tool calls
  │
  ├─ SanityChecker (capability check, gpt-4.1-nano, ~1s)
  │     ↑ reads the raw player input directly (no Resolver dependency)
  │     ↑ rejects the WHOLE turn coherently if any subaction is impossible
  │     ↑ runs BEFORE Resolver — never burn a reasoning-model call on an
  │       action the player can't legally attempt
  │     ↑ world-consistency check is broken & defunct; handled separately
  │
  ├─ Resolver (gpt-5-nano + reasoning + tool calling)
  │     │
  │     ├─ tool: retrieve_rules(query)
  │     ├─ tool: retrieve_facts(query)
  │     ├─ tool: retrieve_npcs(query)
  │     ├─ tool: retrieve_locations(query)
  │     │
  │     └─ emits: ActionPlan
  │              ├─ subactions[]      — decomposed intents (1..N)
  │              ├─ rolls[]           — at most one wave; may have branch_on
  │              ├─ no_roll_outcomes  — structured outcomes for actions needing no roll
  │              ├─ mutations         — sheet/inventory/world/combat deltas (see schema below)
  │              ├─ transition / combatants / destination — cross-cutting signals
  │              └─ deferred_plan.needs_recall — true if branches need outcomes
  │
  ├─ ⏸ awaiting player rolls (if rolls[].any?)
  │
  ├─ Resolver re-call (only when deferred_plan.needs_recall == true)
  │     ↑ sees the prior ActionPlan + the rolls that just landed + outcomes so far
  │     ↑ emits ActionPlan v2: more rolls, or finalize mutations
  │     ↑ recursion bounded by branch depth, not by subaction count
  │
  ├─ Mutations (deterministic) — applies the chosen branch's mutations bundle
  ├─ TimeKeeper / Harbinger / Warmaster — unchanged (consume @loop-tagged data)
  │
  └─ Output phase: Narrate ‖ Loremaster (Stagehand)
                   ContextUpdate retired except for combat-state-only path
```

### Why SanityChecker comes before Resolver

Resolver is the most expensive call in the pipeline (`gpt-5-nano` +
reasoning + tool calls + potentially a recall). Wasting that on an action
the player isn't capable of — or on something the world rules out — is
exactly the loss to avoid.

SanityChecker has no structural dependency on Resolver. Capability check
needs the raw intent + the sheet; both are available pre-Resolver.
Compound input ("I sneak in, attack, then loot the body") gets evaluated
once on the full raw input — if any subaction is impossible (unknown
spell, missing skill rank, wielding a weapon the character doesn't own),
the **whole turn** is rejected. That's stricter than today's per-subaction
rejection, but it's correct: half-completing a planned chain just to
discover the second half is impossible is worse UX than rejecting it
coherently up front. The DM message cites the specific blocker.

**Prompt change required:** the capability check today sees the
*classified intent* (RollRequest's normalised `:intention`). Pre-Resolver
it sees the raw player input verbatim. For most inputs this is fine —
capability checks operate on rule slugs and item names, both extractable
from raw text. For the rest, the prompt becomes "be tolerant of
conjunctions and noise; reject only on clear capability gaps."

**Headline change:** `Mechanic` (as an AI step) goes away. Resolver emits
structured mutations directly. Mechanic-the-prompt is dead;
mutations-the-deterministic-applier (`apply_mutations`, HP clamping, etc.)
stays exactly as it is.

---

## The output contract — `ActionPlan`

This is the load-bearing piece. Everything downstream reads from it.

```json
{
  "reasoning": "Player wants stealth-then-attack. Stealth result determines whether attack uses sneak-attack damage or starts loud combat.",

  "subactions": [
    { "id": "approach", "intent": "stealth approach the assailant" },
    { "id": "strike",   "intent": "attack the assailant", "depends_on": "approach" }
  ],

  "rolls": [
    {
      "id": "r_stealth",
      "type": "skill_check",
      "skill": "Stealth",
      "dc": 15,
      "rule_slug": "stealth",
      "for_subaction": "approach",
      "take_10_eligible": true,
      "take_20_eligible": false,
      "description": "Sneak up behind the assailant"
    },
    {
      "id": "r_attack",
      "type": "attack_roll",
      "for_subaction": "strike",
      "branch_on": "r_stealth",
      "if_success": {
        "attack_option_id": "longsword_main",
        "modifiers": [{ "kind": "sneak_attack", "dice": "1d6" }],
        "target_aware": false
      },
      "if_failure": {
        "attack_option_id": "longsword_main",
        "target_aware": true,
        "post_resolution": { "start_combat": true, "surprise_round_lost": true }
      }
    }
  ],

  "no_roll_outcomes": [],

  "deferred_plan": {
    "needs_recall": true,
    "trigger": "after_roll_results"
  },

  "transition": null,
  "combatants": ["assailant"],
  "destination": null
}
```

### Field semantics

| Field | Meaning |
|---|---|
| `reasoning` | Model's own explanation of the plan; required for audit (§8 design philosophy) |
| `subactions[]` | The player's intent decomposed; `depends_on` makes ordering and conditional gating explicit |
| `rolls[]` | At most **one wave** per Resolver call; each roll names which subaction it serves and (optionally) which prior roll it branches on |
| `no_roll_outcomes[]` | "I tell the guard my name" lands here with a structured outcome and zero rolls |
| `deferred_plan.needs_recall` | If true, the loop calls Resolver again after rolls land |
| `transition` / `combatants` / `destination` | Same cross-cutting signals today's RollRequest emits; preserved unchanged |

### What ActionPlan emits — full mutation taxonomy

Grouped by *who owns the deterministic apply* on the receiving side, since
that's what determines whether ActionPlan emits a clamped final number or
a delta-to-be-clamped. Resolver emits **deltas**; the Ruby applier clamps,
validates, and persists.

#### 1. Sheet mutations (player + creatures)

Flow into the existing `Mutations` deterministic applier.

| Field | Shape | Example |
|---|---|---|
| `hp_change` | signed int per target | `{ "target": "self", "hp_change": -8 }`, `{ "target": "creature_42", "hp_change": +12 }` |
| `add_conditions` | array of condition slugs | `{ "target": "creature_42", "add_conditions": ["prone", "shaken"] }` |
| `remove_conditions` | array of condition slugs | `{ "target": "self", "remove_conditions": ["fatigued"] }` |
| `temporary_hp` | int (sets, doesn't add) | `{ "target": "self", "temporary_hp": 5, "duration_rounds": 10 }` |
| `nonlethal_damage` | signed int | `{ "target": "creature_42", "nonlethal_damage": 6 }` |
| `ability_damage` | hash: ability → int | `{ "target": "self", "ability_damage": { "str": 2 } }` (poison, drain) |
| `spell_slot_used` | level + count | `{ "spell_slot_used": { "level": 3, "count": 1 } }` |
| `class_resource_used` | id + count | `{ "class_resource_used": { "id": "smite_evil", "count": 1 } }` |
| `applied_buffs` | array of buff records | `{ "applied_buffs": [{ "id": "shield", "source_type": "spell", "duration_rounds": 50, "adjudicated_effects": [...] }] }` (existing today) |
| `removed_buffs` | array of buff ids | `{ "removed_buffs": ["mage_armor"] }` (dispel, expired) |

#### 2. Inventory mutations

Three operations; existing applier supports all of them today.

| Field | Shape | Example |
|---|---|---|
| `items_gained` | array of `{item_definition_id, quantity, equipped_slot?}` | `{ "items_gained": [{ "item_definition_id": 144, "quantity": 1 }] }` (loot, craft, find) |
| `items_lost` | array of `{adventure_sheet_item_id, quantity}` | `{ "items_lost": [{ "adventure_sheet_item_id": 891, "quantity": 1 }] }` (consumed, dropped, stolen) |
| `items_equipped` / `items_unequipped` | array of `{adventure_sheet_item_id, slot?}` | `{ "items_equipped": [{ "adventure_sheet_item_id": 891, "slot": "main_hand" }] }` |
| `currency_change` | hash: pp/gp/sp/cp → signed int | `{ "currency_change": { "gp": +25, "sp": -5 } }` |

#### 3. World-state mutations

These bypass the `Mutations` applier and route through the `Lore::Apply*`
writers directly. Single-writer principle (§18) preserved.

| Field | Shape | Owner | Example |
|---|---|---|---|
| `narrative_facts` | array of `{text, kind, entities, polarity}` | `Lore::ApplyResults` | "the door is now unlocked", "the bartender is dead". Loremaster still runs in the output phase to catch anything Resolver missed. |
| `npcs_introduced` | array of `{name, role, attitude, description, location_id?}` | `Lore::ApplyNpcs` | "I greet the merchant" → if the merchant doesn't exist yet, Resolver introduces him inline. Today Loremaster's job. |
| `npc_attitude_change` | array of `{npc_id, new_attitude, reason}` | direct on `AdventureNpc` | "I insult the captain" → captain shifts hostile. |
| `location_visited` | `{location_id}` or `{name, description}` for a new location | `Lore::ApplyLocations` + `Adventure.current_location_id` update | Replaces today's TimeKeeper journey-code branch that does `update_player_position!`. |
| `facts_invalidated` | array of `{fact_id, replacement_text?}` | `Lore::ApplyResults` | "I burn the contract" → invalidates "the contract is in my pack". Today Loremaster's job; Resolver can do it inline when the action *is* the cause. |

#### 4. Combat-state mutations

Bypass the dead `Mechanic`/`CombatGM`/`ContextUpdate` AI layer entirely.
Resolver emits structured deltas; deterministic code applies.

| Field | Shape | Owner | Example |
|---|---|---|---|
| `combat_initialization` | full `combat_context` hash (turn order, participants, action economy) | `Battlefield::PersistCombatStart` | "I attack the assailant" with no current combat → start one. Replaces today's Warmaster + ContextUpdate combat-init path. |
| `combat_state_advancement` | partial hash (current_turn, round, etc.) | `ContextUpdate` deep-merge logic (this part stays) | Mid-combat free-text turn updates. |
| `combat_end` | `{reason}` | `Battlefield::ArchiveCombatEnd` + `combat_context.active = false` | All hostile NPCs at 0 HP, surrender, or flee. |
| `attack_resolutions` | array per resolved attack | `CombatMechanicResolution` (deterministic clamping stays) | Resolver picks `attack_option_id`; clamping resolves DC/damage/defense from the sheet. |
| `battlefield_patches` | array of grid ops (`move_token`, `place_token`, `shift_viewport`) | `Battlefield::ApplyPatches` | Today emitted by CombatGM; Resolver inherits the same schema. |

#### 5. Cross-cutting / bookkeeping signals

Set tags or fields on the `AdventureLoop` for downstream code. Today
scattered across multiple steps' outputs.

| Field | Shape | Consumer | Example |
|---|---|---|---|
| `time_estimate` | `{kind: "action"\|"journey"\|"rest"\|"wait", value, unit, confidence}` | `TimeKeeper` | "I rest 8 hours" → `{kind: "rest", value: 8, unit: "hours"}`. TimeKeeper still owns the deterministic clock arithmetic and Harbinger interrupt; Resolver just provides the estimate. Action/combat use fixed values — no field needed. |
| `transition` | `combat_start` \| `combat_end` \| `journey_start` \| `journey_end` \| `null` | Stagehand, EncounterWarmasterBridge | Same shape as today's RollRequest output. |
| `combatants` | array of names | Warmaster | Combat-start input. Same shape as today. |
| `destination` | string | TimeKeeper destination resolver | Same shape as today. |
| `macro_significant` | bool | `macro_narrative_update` step | Whether this turn's outcome warrants a `story_summary` regeneration. Today Intake decides; Resolver takes it over. |
| `adventure_complete` | bool | Output phase | "And so the dragon falls, the kingdom is saved." — final. Same shape as today. |
| `loop_tags` | array of strings | downstream steps via `@loop.tagged?(...)` | `["took_10", "took_20", "auto_success", "encounter_triggered"]`. Today scattered across Mechanic/TimeKeeper/Harbinger writes; Resolver writes them upfront. |

#### 6. Per-roll branched mutations

For each roll Resolver requests, it owns the post-roll outcome
interpretation. The `if_success` / `if_failure` branches each carry a
*partial* mutations bundle drawn from categories 1-5. When the roll
lands, Ruby reads the player's reported result, picks the matching
branch, and applies that bundle through the same deterministic applier
as a no-roll outcome. **This is what kills Mechanic-as-AI-step.**

```json
{
  "rolls": [{
    "id": "r_attack",
    "type": "attack_roll",
    "for_subaction": "strike",
    "if_success": {
      "mutations": { "hp_change": [{ "target": "creature_42", "hp_change": -8 }] },
      "narrative_facts": [{ "text": "the assailant was wounded", "kind": "event", "entities": ["assailant"] }]
    },
    "if_failure": {
      "mutations": {},
      "narrative_facts": [{ "text": "the player swung wide", "kind": "event" }]
    }
  }]
}
```

For *coupled* rolls (the stealth-then-attack case), the `if_failure` of
the gating roll can include `post_resolution.recall: true`. This signals:
"I cannot fully predict the consequences of failure without knowing how
badly; recall me." Most rolls won't need this — they're predictable. The
exceptions (combat-start triggers, social escalation, conditional access)
explicitly opt in.

#### What Resolver does **not** emit

- **Final clamped HP values.** Always deltas; the applier clamps `[-CON, max_hp]`.
- **Dice rolls.** Player rolls their own (honor system, §2); NPC rolls are deterministic via `Combat::NpcTurn`.
- **Final attack DC numbers.** Resolver picks `attack_option_id`; `CombatMechanicResolution` resolves DC from the sheet.
- **Free narrative text.** That's Narrate's job. ActionPlan carries structured outcomes; Narrate writes the prose that wraps them.
- **Loremaster's full output.** Resolver may pre-emit *obvious* facts (the action's direct consequences); Loremaster runs in the output phase to catch the rest. Both routes funnel through `Lore::ApplyResults` so the single-writer principle for `adventure_narrative_facts` is preserved.

### Why "auto vs. decompose" is just output structure

The model decides whether to break into actions or resolve them in one go
by **shape of the emitted plan**:

- 3 subactions, 3 independent rolls, `needs_recall: false` → "auto-resolved with multiple rolls at once"
- 3 subactions, 1 roll gating the next, `needs_recall: true` → "decomposed into a recall chain"
- 0 subactions split, 0 rolls, 1 no_roll_outcome → "no decomposition needed, no rolls needed"

Same prompt, same model — the decision lives in the JSON shape, not in a
pre-step classifier.

---

## The recall pattern (replaces the action queue)

```
1. Resolver call #1     → emits ActionPlan v1 with rolls[wave 1]
2. Pause, collect rolls (only if rolls[].any?)
3. If plan.deferred_plan.needs_recall:
     Resolver call #2   → reads ActionPlan v1 + rolls + outcomes; emits ActionPlan v2
4. Repeat 2-3 until !needs_recall
5. Apply mutations from final ActionPlan
6. Output phase
```

- **Simple case** ("I climb the wall"): 1 Resolver call, 1 roll, no recall.
  Same shape as today's RollRequest.
- **Stealth-then-attack** (your example): 1 Resolver call, 1 roll, 1 recall
  after stealth lands, finalize.
- **5-action exploration sweep with independent outcomes**: 1 Resolver call,
  5 rolls in one wave, no recall.
- **Conditional chain** ("scout for a tree, cut it down if found"): 1
  Resolver call (scout roll), 1 recall (with scout result, plan cut),
  possibly 1 more recall (cut roll).

`progressive_continuity` semantics are baked in: every recall sees the
prior plan and the prior outcomes. There is no toggle to maintain.
`DmConfig["action_queue"]` is deleted entirely.

### Where the resumed pipeline picks up — the entry-service seam

A turn under unified Resolver is **up to three Sidekiq jobs**, not one. The
pause for player rolls is the same job-ends / job-starts pattern today's
pipeline already uses; Resolver inherits it unchanged.

```
T0  Player submits "I sneak in and attack"
    └─ AdventureMessagesController#create
         ├─ persists player message
         ├─ enqueues PipelineJob (registry_entry_uuid = U)
         └─ returns 202

T1  PipelineJob runs (worker process):
    └─ DungeonMaster::EntryServices::PromptExecution
         ├─ Intake          (~1s)
         ├─ SanityChecker   (~1s)
         ├─ Resolver call #1 (~5s) → emits ActionPlan v1
         │       └─ rolls = [r_stealth, r_attack(branch_on: r_stealth)]
         │       └─ deferred_plan.needs_recall = true
         ├─ @loop.set("action_plan", plan_v1); @loop.set("plan_revision", 1)
         ├─ persists roll_request AdventureMessage("Roll Stealth DC 15")
         ├─ PipelineRegistryEntry[U].status = "paused"
         └─ Job ends. Worker free.

T2  Player rolls 17 in browser
    └─ AdventureMessagesController#submit_rolls
         ├─ persists roll_result message
         ├─ enqueues RollPipelineJob (registry_entry_uuid = U)
         └─ returns 202

T3  RollPipelineJob runs:
    └─ DungeonMaster::EntryServices::ResumePipelineExecution    ← entry seam
         ├─ Loads PipelineRegistryEntry[U] (status = "paused")
         ├─ Loads AdventureLoop, reads @loop.get("action_plan") → plan_v1
         ├─ Loads roll_results since pause
         │
         ├─ ResolverResume     ← NEW; replaces today's resume-into-Mechanic path
         │   ├─ Builds context = {plan_v1, roll_results, prior_outcomes}
         │   ├─ if plan_v1.deferred_plan.needs_recall:
         │   │     Resolver call #2 (~4s) → emits plan_v2
         │   │       case A — plan_v2.rolls.empty? → continue inline
         │   │       case B — plan_v2.rolls.any?:
         │   │           ├─ @loop.set("action_plan", plan_v2)
         │   │           ├─ @loop.set("plan_revision", 2)
         │   │           ├─ persist new roll_request message
         │   │           ├─ status = "paused"
         │   │           └─ job ends → loops back to T2 with plan_v2 active
         │   └─ else (no recall): use plan_v1 as final
         │
         ├─ Mutations applier (sheet/inventory/world/combat from chosen branches)
         ├─ TimeKeeper, Harbinger, Warmaster
         ├─ Stagehand output phase (Narrate ‖ Loremaster)
         └─ PipelineRegistryEntry[U].status = "completed"
```

### The two new pieces

| Component | Role |
|---|---|
| `Steps::Resolver` | The first-call AI step. Lives at the same layer as today's `Steps::RollRequest`. |
| `Steps::ResolverResume` | The post-roll AI step. Owns the recall decision, the inline-vs-pause-again branch, and the hand-off to Mutations. Lives at the same layer as today's `AdventureLoopResolution#resume_after_rolls`, and is dispatched by the unchanged `EntryServices::ResumePipelineExecution`. |

Everything outside these two — `AdventureMessagesController`,
`PipelineJob` / `RollPipelineJob`, `PipelineRegistryEntry`, the pause
state machine, the ActionCable broadcasts — is **unchanged**. The
controller and the Sidekiq job already know how to hit
`ResumePipelineExecution`; we're only changing what *it* delegates to.

### Recall depth cap

`AdventureLoop.data["plan_revision"]` is incremented on every Resolver
re-call. Hard cap at **3 revisions** per turn. Anything deeper is a
misbehaving model — log a `resolver_recall_cap_exceeded` PlayLog event
and force-finalize with whatever mutations the latest plan carries
(possibly an empty bundle). This is the kind of bounded-recursion guard
the design philosophy §15 ("no text-parsing fallbacks") demands at the
boundary between AI and code.

### Player UX

From the player's seat nothing visibly changes vs. today:
- Submit input → thinking indicator → either rolls to make or narrative back.
- If rolls come back, roll → thinking indicator → either more rolls or narrative.
- The Resolver-call count under the hood is invisible; what they see is
  the number of *roll prompts*, bounded by branch depth (and capped at 3).

---

## Tool calling

Resolver uses OpenAI's tool-calling API rather than today's prefilled-RAG
approach. Four tools:

```ruby
TOOLS = [
  { type: "function",
    function: {
      name: "retrieve_rules",
      description: "Find PF1e rules relevant to a query (skill, action type, edge case).",
      parameters: { type: "object", properties: { query: { type: "string" } } } } },
  { type: "function",
    function: {
      name: "retrieve_facts",
      description: "Find established narrative facts relevant to a query.",
      parameters: { type: "object", properties: { query: { type: "string" } } } } },
  { type: "function",
    function: {
      name: "retrieve_npcs",
      description: "Find NPCs in this adventure relevant to a query.",
      parameters: { type: "object", properties: { query: { type: "string" } } } } },
  { type: "function",
    function: {
      name: "retrieve_locations",
      description: "Find locations in this adventure relevant to a query.",
      parameters: { type: "object", properties: { query: { type: "string" } } } } }
]
```

All tool implementations dispatch to the existing pgvector lookups
(`Lore::FactsLookup`, `NpcsLookup`, `LocationsLookup`, `Rules::Lookup`).
The embedding cache from PR #125 covers any duplicate-text case.

### Why tools instead of pre-fetching

Today's RollRequest pre-fetches top-K facts/rules/NPCs/locations *just in
case*. Telemetry (`roll_request_invented_slug` events) shows the model
emits rule_slugs that weren't in the retrieved set ~5% of the time —
suggesting the retrieved set wasn't load-bearing on those calls. Tools let
the model decide what it needs, ask for only that, stop there.

| Intent | Tool calls | Today's pre-fetch |
|---|---|---|
| "I look at the door" | 0 | 4 (always) |
| "I cast Dispel Magic on the wizard's Mage Armor" | 2-3 | 4 (always) |
| "I climb the wall" | 1 | 4 (always) |

**Pay only for what you use.**

### Risk: tool-call round-trips

Tool calling adds round-trips inside the Resolver step (model decides →
tool call → result → model continues). On `gpt-5-nano` with
`reasoning_effort: low`, expect 2-4 tool round-trips per Resolver call
adding ~1.5-3s of internal latency.

Mitigations:
- **Parallel tool calls.** OpenAI supports requesting multiple tools in one
  assistant turn. We execute all of them concurrently and return all
  results in one tool message. Reduces 4 round-trips to 2.
- **Embedding cache.** Already eliminates redundant tool work within a
  pipeline run.
- **Cumulative win.** Today's pipeline pays for retrieval *every* turn,
  load-bearing or not. Resolver pays only when needed.

---

## What dies (in this PR)

| What | Why |
|---|---|
| `Steps::Sequencer` + template + StepRegistry entry + ModelHints | Subsumed by Resolver |
| `Steps::RollRequest` + `Steps::CombatRollRequest` + templates + Context value objects | Subsumed by Resolver (one step; combat detection is internal) |
| `Steps::Mechanic` + template | Subsumed by Resolver — mutations come straight from the ActionPlan |
| `Pipeline::ActionQueueRunner`, `Phases::OrchestrateCompoundActions`, `Narrative::ProgressiveEntry`, `Narrative::AccumulatedAssembly`, `Narrative::SingleActionAssembly`, `Narrative::NarrationPhaseInputs` | Recall pattern replaces queue orchestration; one narrative per turn |
| `DmConfig["action_queue"]` + `progressive` / `progressive_continuity` / `false` modes | Single behavior, no toggle |
| `AdventureLoop.sequence_index` semantics | Single loop per pipeline run |
| `Phases::CombatMechanicResolution` | Resolver emits a resolved attack-option; clamping moves into the deterministic mutations applier |
| `RollRequest::Context`, `CombatRollRequest::Context` builders | Replaced by Resolver's runtime context object |
| Prefilled scene retrieval at the start of every step | Replaced by tool calls inside Resolver |

Roughly **25-40 files deleted**; pipeline goes from 12+ AI steps to 4
(Intake, Resolver, Loremaster, Narrate) plus combat-HUD-specific code.

---

## What survives

| What | What changes |
|---|---|
| `Intake` | Stays as cheap nano-class moderation gate. May lose its "classify domain" output (Resolver decides). |
| `SanityChecker` capability check | Still runs; reads per-subaction intents from ActionPlan instead of from RollRequest output. World-consistency check is already defunct and is handled in a separate effort. |
| `Mutations` deterministic applier | Unchanged — JSON shape it receives is the same. |
| `TimeKeeper`, `Harbinger`, `Warmaster`, `EncounterWarmasterBridge` | Unchanged — they consume `:loop`-tagged data Resolver writes via existing `@loop.set(...)` seams. |
| `Stagehand` output phase | Unchanged structure (Narrate ‖ Loremaster) — input shape from one ActionPlan instead of merged-from-N-loops. |
| `Combat::PlayerActionResolver` + HUD | Unchanged — server-authoritative deterministic combat HUD remains the fast path. |
| `Combat::NpcTurn` engine | Unchanged. |
| `EmbeddingCache` (PR #125) | More valuable — Resolver's tool calls all benefit. |
| Parse-error retry (PR #125) | More valuable — one big call is more likely to truncate; retry covers it. |

---

## Migration order (within the single PR)

Each commit leaves the test suite green and local play working.

### Commit 1 — Resolver scaffolding (no production behavior change)

- `Steps::Resolver` skeleton with the OpenAI tool-calling loop.
- `ActionPlan` value object + JSON schema (used both for OpenAI Structured
  Outputs *and* for the Ruby parser/validator).
- Tool dispatch layer: maps tool names → existing pgvector lookups.
- Unit tests for tool-call dispatch, plan parsing, recall trigger logic.
- Wire into pipeline behind a feature flag (`unified_resolver_enabled`
  on DmConfig). Default `false`.

### Commit 2 — Pipeline integration

- `Pipeline::ResolverPhase` replaces `OrchestrateCompoundActions` when
  flag is on.
- Recall logic: one loop, recursive Resolver calls until plan has no
  `needs_recall` and all rolls resolved.
- SanityChecker capability check rewires to read per-subaction intents.

### Commit 3 — Mutations from ActionPlan

- Apply mutations directly from Resolver's emitted plan.
- `CombatMechanicResolution` clamping moves to a deterministic
  post-Resolver pass.
- Mechanic step still callable on flag-off path; flag-on bypasses it.

### Commit 4 — Output-phase rewiring

- Stagehand's `narration_context.combined_seed` builds from one ActionPlan
  instead of merged-loop sources.
- Narrate prompt updated to consume ActionPlan's outcome shape.
- Loremaster unchanged (already operates on post-mutation outcome).

### Commit 5 — Flip the flag, delete the dead path

- `unified_resolver_enabled` defaults to `true`.
- Delete: Sequencer, RollRequest, CombatRollRequest, Mechanic, action
  queue runner, progressive narration modes, multi-loop sequencing,
  intermediate value objects.
- Update docs:
  - `README.md` (pipeline diagram + step table)
  - `docs/pipeline_steps.md` (large rewrite)
  - `docs/pipeline_diagram.md` (new mermaid)
  - `docs/design_philosophy.md` §3 ("Structured decomposition") gets a
    careful update — the principle is still right, but the conclusion
    has shifted: when the model is capable enough, externalizing the
    chain of thought through tool calls is preferable to externalizing
    it through pipeline steps.

---

## Deferred to follow-up PRs

### Combat HUD ↔ Resolver integration

Today the combat HUD is the deterministic happy path; CombatRollRequest is
the free-text escape hatch. Under unified Resolver, free-text combat just
becomes Resolver-with-combat-context. But the *HUD itself*
(`Combat::PlayerActionResolver`, `NpcTurn` engine) is rightly outside the
AI flow — those are server-authoritative dice + clamping. The integration
question — does the HUD action produce an ActionPlan-shaped record so
Stagehand can narrate it uniformly? — is its own design.

### Loremaster + Narrate prompt tuning

Their *inputs* change because the input source changes (one plan vs.
merged loops). Prompts probably want tightening but the *shape* change is
mechanical. Treat any quality tuning as follow-up.

### Cost telemetry

With tool calls, the question "how much did this turn cost?" becomes more
variable. The Resolver step's `AiUsageRecord` will show input + output +
reasoning + tool-call tokens, but understanding the cost distribution
across turn types (simple vs. compound vs. branch-heavy) needs production
data. Land the change first; instrument and tune second.

---

## Risks

### Reasoning-model latency variance

A Resolver call at `reasoning_effort: low` might complete in 3s on a
simple turn and 12s on a complex one. Today the user sees a steady stream
of progress events; under unified Resolver they see one long "thinking"
period.

**Mitigation:** emit progress events from inside the tool-call loop
("Looking up rules…", "Considering enemy positioning…") so the indicator
stays alive. We already have the `broadcast_progress` plumbing for this.

### Tool-calling reliability on `gpt-5-nano`

Cheap reasoning models are still maturing on tool use. We may see
malformed tool calls, ignored tool results, or refusal to use tools when
the model "thinks" it knows.

**Mitigation:**
- Existing parse-error retry (PR #125) covers some of this.
- Worst case, bump Resolver to `gpt-5-mini` or `gpt-5`. Cost goes up but
  this is exactly the "more capable, fewer steps" trade we want at this
  stage.

### Recall debuggability

Today, looking at PlayLog you see a clear linear trace: intake →
sequencer → roll_request_1 → roll_request_2 → mechanic_1 → mechanic_2 →
narrate. Under recall, you see: resolver_call_1 → (player rolls) →
resolver_call_2 → narrate. Each Resolver call is bigger and more opaque.

**Mitigation:** the `parsed_response` of each Resolver call must clearly
show the ActionPlan it emitted, the rolls it requested, and the recall
trigger reason. Every tool call inside Resolver gets its own PlayLog
sub-event linked to the parent. Admin > Play Logs gets a Resolver-aware
view that visualizes the recall chain.

### Sanity check capability scope

Today the capability check sees one focused intent at a time. It now sees
`subactions: ["pick lock", "open door", "loot chest"]` together. Probably
fine for capability (the sheet either has the skill or it doesn't), but
the prompt has to handle arrays cleanly.

### Migration of existing in-flight adventures

Pre-launch this is moot. Post-launch it would matter. Noting it for
completeness only — we're not migrating anything.

---

## Cost / latency rough estimate

### Today, simple out-of-combat turn

| Step | Model | Tokens in/out | Cost | Latency |
|---|---|---|---|---|
| intake | nano | 800 / 120 | $0.00006 | 1.5s |
| sequencer | nano | 600 / 80 | $0.00004 | 1.3s |
| roll_request | gpt-5-nano | 2K / 600 (incl. reasoning) | $0.00040 | 2.5s |
| sanity_checker | nano | 1K / 60 | $0.00007 | 1.1s |
| mechanic | nano | 9K / 660 | $0.00072 | 2.1s |
| time_keeper | nano | 800 / 100 | $0.00006 | 1.0s |
| **Subtotal pre-narrative** | | | **~$0.00135** | **~9.5s** |
| narrate + ContextUpdate + Loremaster fan-out | varies | | ~$0.0010 | ~5s (parallel) |

### After Resolver, simple out-of-combat turn

| Step | Model | Tokens | Cost | Latency |
|---|---|---|---|---|
| intake | nano | 800 / 120 | $0.00006 | 1.0s |
| Resolver (1 wave, no recall) | gpt-5-nano + tools | ~3K / ~1500 incl. tool I/O & reasoning | $0.00100 | 4-6s |
| sanity_checker capability | nano | 800 / 60 | $0.00006 | 1.0s |
| **Subtotal pre-narrative** | | | **~$0.00112** | **~6-8s** |
| narrate + Loremaster | unchanged | | ~$0.0009 | ~4s |

**Net for simple turn:** ~$0.0003 cheaper, ~1.5-3s faster.

### After Resolver, stealth-then-attack with recall

Roughly equal cost to today (one big Resolver + recall ≈ today's
intake + sequencer + 2 RollRequests + 2 Mechanics) but with **correct
branching behavior we don't get today**.

---

## Open question I want resolved before coding

**The exact ActionPlan JSON schema.**

I'll draft a strict JSON Schema (used both for OpenAI Structured Outputs
*and* for the Ruby parser/validator) and put it in front of you for review
before any pipeline code. The schema is the contract that determines how
much Mechanic-style code lives where; getting it right is the
highest-leverage decision in the whole plan.

---

## Sequencing relative to PR #125

PR #125 (cache-intent-embeddings + parse_error retry + scene_update
removal) lands first. This epic builds on top of:

- The `EmbeddingCache` becomes more valuable under Resolver tool calls.
- The `parse_retry` mechanism is critical insurance for big Resolver calls.
- The scene_summary subsystem retirement is a prerequisite — this epic
  shouldn't have to reason about a feature we just deleted.

Resolver work begins after PR #125 merges.
