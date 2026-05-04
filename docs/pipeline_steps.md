# Dungeon Master Pipeline — Step Reference

Design document describing the AI Dungeon Master pipeline: what each step
does, what it receives, what it produces, and how the steps connect.

**Flow diagram:** [Pipeline diagram](pipeline_diagram.md) (Mermaid flowcharts).

For the guiding principles behind these decisions, see
[Design Philosophy](design_philosophy.md).

For flow and behavioral detail see [pipeline_diagram.md](pipeline_diagram.md).

---

## Outer orchestration (Pipeline class)

The **AI step mixins** (Intake, Sequencer, Narrate, …) implement individual prompts; **`AdventureLoopResolution`** (also mixed into `PipelineEngine`) drives evaluation → sanity → mechanics for each **AdventureLoop** row; the **`DungeonMaster::PipelineEngine`** class wires the **player turn** and **action queue**. Reorder or extend the main line by editing **`#run_prompt`** in [`app/services/dungeon_master/pipeline_engine/concerns/entry_points.rb`](../app/services/dungeon_master/pipeline_engine/concerns/entry_points.rb) (three explicit `apply_prompt_phase` calls).

| Phase / component | Role | Source |
|-------------------|------|--------|
| **`#run_prompt` + `#apply_prompt_phase`** | Ordered calls: intake + danger gate → DM query branch → sequencer + compound-action loop | [`pipeline_engine/concerns/entry_points.rb`](../app/services/dungeon_master/pipeline_engine/concerns/entry_points.rb) |
| **`Phases::IntakeDangerGate`** | `run_intake`; danger threshold → `:rejected` | [`pipeline_engine/phases/intake_danger_gate.rb`](../app/services/dungeon_master/pipeline_engine/phases/intake_danger_gate.rb) |
| **`Phases::DmQueryBranch`** | Ask DM mode / `is_dm_query` → `run_dm_query_flow` | [`pipeline_engine/phases/dm_query_branch.rb`](../app/services/dungeon_master/pipeline_engine/phases/dm_query_branch.rb) |
| **`Phases::OrchestrateCompoundActions`** | `run_sequencer` then **`ActionQueueRunner`** | [`pipeline_engine/phases/orchestrate_compound_actions.rb`](../app/services/dungeon_master/pipeline_engine/phases/orchestrate_compound_actions.rb) |
| **`PipelineEngine::Concerns::EntryPoints`** | `run_prompt` / `run_initiative` / `run_rolls`, phase chain (`apply_prompt_phase`), `run_dm_query_flow`, `run_remaining_queue`. | [`pipeline_engine/concerns/entry_points.rb`](../app/services/dungeon_master/pipeline_engine/concerns/entry_points.rb) |
| **`PipelineEngine::Concerns::NarrationCoordination`** | `run_accumulated_narrative_phase`, `run_single_action_narrative_phase`, action-queue mode helpers (`per_action_narration?`, …). | [`pipeline_engine/concerns/narration_coordination.rb`](../app/services/dungeon_master/pipeline_engine/concerns/narration_coordination.rb) |
| **`PipelineEngine::Concerns::ContextCoordination`** | `run_inter_action_context_update`, `run_context_updates_at_encounter_pause`. | [`pipeline_engine/concerns/context_coordination.rb`](../app/services/dungeon_master/pipeline_engine/concerns/context_coordination.rb) |
| **`PipelineEngine::ActionQueueRunner`** | For each queued action: `AdventureLoop` + `AdventureLoopResolution#resolve`; dispatches on `:status`; **abort** whole turn on `:rejected` (fresh) vs **skip** action (resume). Ends in **`run_accumulated_narrative_phase`** / `:narrated_sequence`. | [`pipeline_engine/action_queue_runner.rb`](../app/services/dungeon_master/pipeline_engine/action_queue_runner.rb) |
| **`PipelineEngine::ActionQueueLog`** | Per-action `action_label` on the pipeline log + `play_log!` for queue pause / interrupt / completed. | [`pipeline_engine/action_queue_log.rb`](../app/services/dungeon_master/pipeline_engine/action_queue_log.rb) |
| **`Narrative::AccumulatedAssembly`** | Merges resolver results + `AdventureLoop` `pipeline_outcome` rows into `PipelineContext` / mutations / `extra` for **`#run_accumulated_narrative_phase`**. | [`narrative/accumulated_assembly.rb`](../app/services/dungeon_master/narrative/accumulated_assembly.rb) |
| **`Narrative::SingleActionAssembly`** | One-loop `PipelineContext` for progressive per-action narration (`prior_outcomes` when `progressive_continuity`). | [`narrative/single_action_assembly.rb`](../app/services/dungeon_master/narrative/single_action_assembly.rb) |
| **`Narrative::NarrationPhaseInputs`** | Intent + `PipelineContext` + mutations + optional Stagehand `extra`; return type of `AccumulatedAssembly` / `SingleActionAssembly` for `run_narrative_phase`. | [`narrative/narration_phase_inputs.rb`](../app/services/dungeon_master/narrative/narration_phase_inputs.rb) |
| **`Narrative::ProgressiveEntry`** | Value object for each progressive narration payload: DM text, `adventure_complete`, queue indices, `action_text`. Built after `run_narrative_phase`; `#to_h` is passed to `on_narrative` and into `:narratives` on `:narrated_sequence`. | [`narrative/progressive_entry.rb`](../app/services/dungeon_master/narrative/progressive_entry.rb) |

**Per-class contracts** (what must be set on the pipeline before the step, what mutates, prompt inputs) live in the file header comments on each phase and on `ActionQueueRunner`.

`AdventureLoopResolution` now emits typed flow payloads through `DungeonMaster::PipelineFlowResults` (backward-compatible alias: `DungeonMaster::FlowResults`) and only serializes to hashes at the boundary consumed by queue orchestration and resume entrypoints.

Combat attack rolls now follow the same AI-picks / server-resolves pattern as saving-throw `dc_formula`: combat mech-eval selects an `attack_option_id`, and Ruby resolves attack mode, defense targeting, damage metadata, and pending-roll quick actions from that code-built option.

**Adding a conditional outer step:** insert a phase class in `pipeline/phases/`, implement `.call(pipeline, state)` returning `{ halt: true, result: ... }` to stop the chain or `{ halt: false, ... }` to merge keys into `state`, then add **`return r if (r = apply_prompt_phase(Phases::YourPhase, state))`** (or equivalent) in **`#run_prompt`** in the desired order.

---

## Design Decisions

Architectural choices that shaped the pipeline, why each alternative was
rejected, and what trade-offs we accepted.

### 1. Sequential pipeline of small prompts vs. single monolithic prompt

**Decision:** break the AI interaction into focused calls instead of
one large "do everything" prompt. 
**Why:** the original architecture used a single prompt that received the
player input, all context, all rules, and was expected to sanitize,
adjudicate, narrate, and update state in one pass. This had compounding
problems:

- **Accuracy degrades with task count.** When a model handles
  sanitization, classification, rules lookup, mechanical resolution,
  narrative writing, and context updates simultaneously, each sub-task
  gets less attention. Verdict accuracy suffered most — the model would
  skip attack-of-opportunity triggers or misapply grapple rules because
  it was also thinking about prose quality.
- **Token budgets are impossible to tune.** A single call needs a budget
  large enough for the worst case (long narration + complex multi-context
  verdict), wasting tokens on simple turns.
- **Debugging is opaque.** When the output is wrong, you can't tell
  which sub-task failed. With separate calls, each step has its own log
  entry, reasoning field, and model attribution.
- **Model selection is locked.** Some tasks (mechanical evaluation)
  benefit from reasoning models; others (narration) benefit from creative
  models. A single call forces one model for everything.

**Trade-off accepted:** higher latency (multiple serial round-trips) and
slightly higher total token usage (repeated context in each prompt).
We accepted this because correctness and debuggability matter more than
speed for a turn-based game, and per-step model selection recovers most
of the cost overhead by using cheap models on cheap steps.

**Current path:** `AdventureLoopResolution#resolve` dispatches deterministically on combat state — out of combat → `Steps::RollRequest`, in combat → `Steps::CombatRollRequest`. Both are single AI calls that emit a single roll spec (or "no roll") plus the cross-cutting signals downstream code consumes (affected_contexts, expand_scene, transition, combatants, destination). UnifiedEvaluation and ParallelEvaluation have both been retired — see Decision 4.

### 2. Combat context plus pgvector stores instead of six JSONB context blobs

**Decision:** the only structured per-adventure JSONB state is
`combat_context` (live combat: turn order, round, participant HP /
conditions / positions) and `time_context` (the clock). Everything that
used to live in `traversal_context`, `social_context`,
`exploration_context`, `rest_context`, and `inventory_context` is now in
purpose-built relational + pgvector stores: `adventure_npcs`,
`adventure_locations`, and `adventure_narrative_facts`. Each downstream
step retrieves only the slice it needs by cosine similarity against the
player's intent or outcome.

**Why micro-contexts went away:** the JSONB blobs grew freeform
schemas that the AI had to maintain across every turn, and the
ContextUpdate step had to reason about all of them in a single prompt
even when only one slice was relevant. Schema drift, stale carry-forwards,
and "missing field" surprises were common failure modes. Snapshots also
forced lossy summarisation — once an NPC fell out of `nearby_npcs`, it
was effectively gone, even if it was still narratively relevant.

The pgvector stores fix this by inverting the data flow. Steps no longer
receive a precomputed snapshot — they retrieve relevant rows on demand:

- **`adventure_npcs`** — per-adventure NPCs (`name`, `role`, `attitude`,
  `description`, `location_id`, embedding). Retrieved by similarity
  against the current intent. Sole writer: `Lore::ApplyNpcs` (called
  from Loremaster).
- **`adventure_locations`** — per-adventure locations (`name`,
  `description`, deterministic `(x, y)` placement, embedding). Retrieved
  by similarity. Sole writer: `Lore::ApplyLocations`.
- **`adventure_narrative_facts`** — durable facts (events, states,
  entities), each with `source` (`seed`, `loremaster`, …),
  `introduced_at_loop_id`, and `invalidated_by_fact_id` for state
  replacement. Sole writer: Loremaster's `Lore::ApplyResults` (see §37).

**Combat context is the exception** because it is not retrievable —
turn order and HP must be authoritatively present every turn, not
fuzzily looked up. It also stays small (one active combat at a time)
and has a stable schema that the combat-only pipeline owns.

**Trade-off accepted:** turn-time prompts now embed the intent and
issue cosine-similarity queries instead of reading a single JSONB
column. The cost is two embeddings per turn (one for retrieval, one
batched after Loremaster); the win is that prompt size stays bounded
no matter how rich the adventure becomes.

### 3. App-side NPC roll resolution

**Decision:** the application rolls dice for NPCs using `rand(1..20)`,
not the AI.

**Why:** if the AI resolves NPC rolls, it can:
- Fudge results to fit a narrative it wants to tell
- Produce results that don't match the NPC's actual stat block
- Be inconsistent about which modifiers it applies

In active combat, NPC turns are now resolved entirely by the
deterministic `Combat::NpcTurn` engine driven off each creature's
`behavior_policy` JSONB — no per-NPC AI call. AI is only consulted on
the player's free-text turn (CombatRollRequest, single call) and on the
end-of-round flavor pass (`CombatNarratorJob`, async, narration only).

**Player rolls are different:** the player submits their own roll results
via the UI. This is a deliberate engagement choice — rolling dice is part
of the tabletop experience. The app trusts the player's reported values
(honor system, as in a real tabletop game).

### 4. RollRequest / CombatRollRequest as the sole evaluation path, and action_queue narration modes

#### Evolution of the evaluation step

The pipeline's evaluation step has gone through three generations:

1. **Per-domain chain (retired):** six parallel beacon AI calls → up to six sequential MechanicalEvaluation calls → up to six parallel RollQualifier calls. 8–14 concurrent OpenAI calls per turn, stressed the DB connection pool, and frequently produced duplicate rolls because each domain evaluated independently.
2. **UnifiedEvaluation (retired):** one AI call handling all six domains in a single prompt. Fixed the parallelism issues but coupled prompt size to total domain count and made per-domain model tuning impossible.
3. **ParallelEvaluation (retired):** restored the 3-phase chain but offloaded concurrency to a dedicated Node.js microservice via `Promise.all`. Recovered observability and per-phase model selection at the cost of three serial round-trips.
4. **RollRequest / CombatRollRequest (current):** a single AI call backed by pgvector RAG over rules (`adventure_narrative_facts` for scene beats, `rule_embeddings` for rule definitions). The prompt carries no character block and no full micro-context dump — just the player's intent, the top-K relevant rules, and the top-K recent narrative facts. Combat-active turns hit `Steps::CombatRollRequest` instead, which augments the prompt with attack options, action economy, threats, and battlefield text. Combat math (DCs, damage, defense kind) resolves post-call from the sheet via `Phases::CombatMechanicResolution`, clamped by the AI-emitted `attack_option_id`.

The 3-phase chain is gone: there are no `beacon`, `mechanical_evaluation`, or `roll_qualifier` AI steps anymore. The Node evaluator microservice still exists and is still used by Stagehand (parallel narrate + context updates), WorldTurn (per-NPC actions in legacy AI-driven combat — currently dead in favor of `Combat::NpcTurn`), the sanity gate, and ContextUpdate fan-outs, but no longer for an evaluation chain.

#### action_queue: the three narration delivery modes

How player input is split and how narratives are delivered is controlled by the single `DmConfig["action_queue"]` key (per-adventure override available via `dm_settings["action_queue"]`):

| | `false` | `"progressive"` (default) | `"progressive_continuity"` |
|---|---|---|---|
| Input splitting | No — compound input treated as one action | Yes — Sequencer splits into ordered actions | Yes — same |
| Per-action narrative | No — single combined narrative at the end | Yes — each resolved action is narrated immediately, broadcast as `pipeline_action_result` before the next action begins | Yes — same |
| Prior-action context | N/A | No — each action evaluated independently | Yes — prior `pipeline_outcome` values from `AdventureLoop` injected into the narrate prompt |
| Pipeline return type | `:narrated` | `:narrated_sequence` | `:narrated_sequence` |

**Trade-off: `"progressive_continuity"` token cost.** Injecting prior outcomes adds tokens to every subsequent evaluation and narration call in a sequence. For a 3-action turn the second and third actions each carry the outcomes of all preceding actions. This is intentional — the AI needs the context — but it means token spend scales with sequence length. This mode is not the default; enable it explicitly when conditional action chains (e.g. "scout for a tree, then cut it down if found") require the second action's evaluation to know the first action's result.

### 5. Mechanic before narration (facts-first ordering)

**Decision:** determine the factual outcome before writing any narrative.
Both mechanical actions (with rolls) and no-roll actions ("I tell the
guard my name") flow through the Mechanic step; for the latter,
RollRequest emits `rolls: []` and Mechanic produces a verdict with no
dice — the same downstream contract.

**Why:** if the model narrates and evaluates simultaneously, narrative
bias corrupts accuracy. The model might write a dramatic "the goblin
collapses!" moment and then produce mutations showing the goblin at 3 HP
— or vice versa, produce correct mutations but a narrative that
contradicts them.

By running Mechanic first, Narrate receives a factual outcome it must
faithfully narrate. Mechanic writes `verdict_outcome` to the adventure
loop, giving Narrate a single read location regardless of whether dice
were rolled.

**Trade-off accepted:** two AI calls where one might suffice. The cost
is justified by correctness — mechanical errors in a Pathfinder game
(wrong HP, missed saves, ignored conditions) directly degrade the
player's trust in the DM.

**Note on retired Momentum step.** Earlier revisions ran a separate
Momentum AI call for non-mechanical actions, parallel to Mechanic. It
was retired in favour of the unified Mechanic path — Mechanic with
empty `rolls` is identical in shape to a no-roll Momentum verdict and
removes the path split.

### 6. Structured mutations instead of natural language

**Decision:** the Mechanic step outputs explicit structured mutations
(`{ "hp_change": -8 }`) rather than prose ("the goblin takes 8 damage").

**Why:** the app must apply these changes to the database. If the AI
produces natural language, the app must parse it — "takes 8 damage",
"loses 8 hit points", "is dealt 8 points of damage" all mean the same
thing but require NLP to extract. Structured JSON is unambiguous and
directly actionable.

This also makes mutations auditable. Every `AiLog` entry for a `mechanic`
step contains the exact mutations that were applied, traceable back to
the rolls and evaluations that produced them.

### 7. Rules fetched by slug from a YAML index

**Decision:** rules are stored as YAML files keyed by slug, embedded
into the `rule_embeddings` pgvector table by the `dungeon_master:rules:embed`
rake task. RollRequest / CombatRollRequest retrieve the top-K relevant
rules per turn via `Rules::Lookup` and inject them into the prompt as
the slug-keyed RAG context.

**Why:** LLMs hallucinate rules. Pathfinder 1e has thousands of rules
with subtle interactions (grapple, combat maneuvers, spell resistance,
damage reduction). If the model recites rules from memory, it will get
details wrong — particularly for less common rules.

By giving the model a rules manifest, we ensure:
- The model is reminded of rules it might otherwise deprioritise
- Rules can be updated or corrected without retraining
- We can audit which rules were surfaced for each evaluation

**Trade-off accepted:** the model must correctly apply relevant rules
from the manifest. This is mitigated by expecting capable models to have
strong Pathfinder 1e rule knowledge already; the manifest is a structured
reminder, not the sole source.

### 8. OGL/SRD-compliant bestiary

**Decision:** creature stat blocks are seeded from an OGL/SRD-compliant
bestiary with a `source` field on each entry, and `CreatureSheet`
instances are created deterministically from bestiary templates.

**Why:** Pathfinder 1e content is published under the Open Game License
(OGL), but not all content is open. Adventure Paths, specific NPCs, and
some monsters are Product Identity. By restricting the bestiary to OGL/SRD
content and tracking the source, we stay within legal bounds.

The deterministic creation (HP rolled from `hp_formula`, stats copied
from the bestiary entry) ensures mechanical consistency. The AI identifies
*which* creature appears via the narrative; the app creates it with real
stats. This prevents the AI from inventing creatures with arbitrary
(often inflated or deflated) stat blocks.

### 9. DM Query fast path

**Decision:** when Intake detects `is_dm_query`, skip the
entire action pipeline and route to a dedicated DM Query step.

**Why:** many player messages are questions ("How does grappling work?",
"What's in my inventory?", "What can I see?"). These don't advance the
game state and shouldn't trigger mechanical resolution, narrative
generation, or context updates.

Routing questions through the full pipeline would:
- Waste many AI calls on a non-action
- Risk context updates reflecting a non-event ("player asked about
  grappling" shouldn't update the combat context)
- Add unnecessary latency for a simple Q&A

**Trade-off accepted:** the DM Query step has no context persistence.
If the player's question reveals something narratively significant ("What
does the inscription say?"), it won't be captured in the story summary.
This is acceptable — if the player acts on the information, that action
will flow through the full pipeline and be captured then.

### 10. ERB templates for prompts

**Decision:** store system prompts as `.text.erb` files under
`app/services/dungeon_master/templates/`, rendered by a
`PromptRenderer` class.

**Why:** the original implementation used Ruby heredocs embedded in a
monolithic `Prompts` module. This had problems:

- Prompts were mixed with Ruby logic, making them hard to read and edit
- Non-developers (game designers) couldn't easily review or modify
  prompts without understanding Ruby
- Prompt diffs in version control were noisy (mixed with code changes)
- Long heredocs degraded IDE readability

ERB templates separate prompt content from logic. The templates read like
plain text with minimal interpolation (`<%= @variable %>`), making them
accessible to anyone who needs to tune the DM's behavior.

**Trade-off accepted:** an extra layer of indirection (renderer class,
file I/O) for what was previously inline strings. This is negligible —
template rendering is sub-millisecond compared to the AI call it feeds.

### 11. Pipeline class separated from entry services

**Decision:** `DungeonMaster::PipelineEngine` encapsulates pure pipeline logic
(step sequencing, branching, data flow). Pipeline entry responsibilities are
split into focused deterministic services under `DungeonMaster::EntryServices`
(`PromptExecution`, `ResumePipelineExecution`) with shared dependency wiring in
`DungeonMaster::EntryRuntime`; `DungeonMasterService` remains a small facade
for controller/job compatibility.

**Why:** the original `DungeonMasterService` was a monolith that mixed
pipeline orchestration, message persistence, error handling, and step
implementations. Reading it required holding the entire flow in your head
to understand any single part.

The separation means:
- `Pipeline#run_prompt` reads like a linear script: intake,
  then branch, then beacon, then mechanics gate, etc.
  A developer can read the full flow in ~40 lines.
- Prompt, roll, and initiative execution each have explicit entry services,
  so moderation/policy/runtime orchestration is not mixed into one monolithic
  class.
- Steps can be tested against the Pipeline without mocking persistence.

**Trade-off accepted:** more files to navigate. Mitigated by consistent
naming and the `DungeonMaster::Steps::*` module convention.

### 12. Per-step model selection

**Decision:** each pipeline step can use a different AI model, configured
via `DmConfig#model_for(step)` with a global default fallback.

**Why:** steps have fundamentally different cognitive demands:

- Intake is a simple assessment — a nano model handles it perfectly
- RollRequest / CombatRollRequest are tightly-scoped structured outputs
  with retrieved-rule grounding — a cheap reasoning model at minimal
  effort is enough
- Narrate requires creative prose — benefits from large, temperature-
  tunable models
- Context Update is structured JSON — a mini model is plenty

A single model for all steps forces a choice between overpaying for
cheap steps or under-serving expensive ones. Per-step selection lets you
put the budget where it matters.

This also future-proofs for fine-tuning: steps with consistent schemas
(intake, roll_request, context updates) are strong fine-tuning candidates.
You can fine-tune a cheap model on logged examples and slot it in for one
step without affecting others.

**Trade-off accepted:** more configuration complexity. The admin UI
mitigates this with per-step suggestions, model cost display, and
sensible defaults.

### 13. Reasoning field on all AI outputs

**Decision:** every pipeline step's JSON schema includes a `reasoning`
field that the model must populate.

**Why:** when something goes wrong (incorrect evaluation, bad verdict,
stale context), the `reasoning` field in `AiLog` reveals *why* the model
made that decision. Without it, debugging requires reconstructing the
model's thought process from the input/output alone.

The field is intentionally brief ("1-2 sentences") to minimize token
overhead. It's logged but never shown to the player.

**Trade-off accepted:** a small amount of output tokens per call (~20-40
tokens). At $0.60/1M output tokens (gpt-4o-mini), this costs roughly
$0.00002 per call — negligible.

### 14. Hard error on finish_reason: length (no graceful degradation)

**Decision:** when the AI returns `finish_reason: length` (token budget
exceeded), the pipeline raises `TokenBudgetExceededError` as a hard
error — even if the response contains partial content.

**Why:** truncated JSON is worse than no JSON. A partial response might
parse successfully but with missing fields, leading to:
- An evaluation with `player_rolls` cut off mid-array
- A verdict with mutations missing NPC entries
- A narration that stops mid-sentence

These partial results would propagate through the pipeline and produce
subtly wrong outcomes that are harder to debug than an outright failure.

The hard error surfaces immediately in logs with
`status: "token_budget_exceeded"`, telling the admin exactly which step
needs a higher budget. The player sees only *"The Dungeon Master is
momentarily distracted..."* — a generic message that doesn't leak
technical details.

**Alternative rejected:** graceful degradation (accepting truncated
responses and filling in defaults) was explicitly rejected. The risk of
silently wrong results outweighs the cost of a visible failure.

### 15. Generic player-facing error messages

**Decision:** all errors are translated to *"The Dungeon Master is
momentarily distracted..."* before reaching the player. Technical
details go to logs only.

**Why:** error messages like "Token budget exceeded on 'sanitize' step
(budget: 300)" leak system internals to the player, breaking immersion
and potentially exposing configuration details. The player doesn't need
to know about token budgets, pipeline steps, or API errors — they need
to know the DM fumbled and they should try again.

Admins have full visibility through `AiLog` records and the admin UI.

### 16. Context update resilience (errors swallowed)

**Decision:** ContextUpdate (combat-only) and Loremaster's apply phase
rescue all errors and return empty hashes instead of failing the pipeline.

**Why:** these writes are important but not critical to the current
turn. If ContextUpdate fails:
- The player still sees their narrative (Narrate runs in parallel)
- The next turn reads a slightly stale combat snapshot, which is
  recoverable on the next successful update

Failing the entire turn because a write errored would be disproportionate
— the player would see an error message for a turn that was otherwise
fully resolved and narrated. Errors are reported through
`@log.report_error` (Sentry) so they remain visible even though the
turn succeeds; see §37 for the lossy-with-Sentry contract Loremaster
follows.

### 17. Parallel execution of independent steps

**Decision:** several step pairs run concurrently in Ruby threads:
- SanityChecker (capability check + world consistency check) — 2 parallel threads on the mechanics path
- Narrate + ContextUpdate (the output phase, in parallel mode)
- Micro Context Update + Macro Narrative Update (within context updates)

**Why:** these pairs write to different data and have no dependencies on
each other's outputs. Running them in parallel saves one or more full AI
round-trips of latency per turn.

Intake runs as a single call (no parallel gate). The former Sanitize +
Classify parallel pair has been merged into Intake.

**Trade-off accepted:** Ruby thread complexity and database connection
pool pressure. Mitigated by wrapping all `Thread.new` blocks with
`ActiveRecord::Base.connection_pool.with_connection` to ensure proper
checkout and return. The connection pool is sized at 12 to accommodate
peak parallelism (~3 concurrent connections: main + 2 sanity gate threads).

### 18. One writer per data store

**Decision:** every per-adventure data store has exactly one writer, and
that writer is named at the seam. No code path may write to a store
that another step already owns.

| Store | Sole writer | Surface area |
|---|---|---|
| `adventures.combat_context` | `Steps::ContextUpdate` | Live combat state. Warmaster emits a deterministic hash that ContextUpdate writes verbatim via a `combat_initialization` mutation. |
| `adventures.time_context` | `Utilities::GameClock` | Code-only clock advancement; no AI call. |
| `adventures.scene_summary` | `Steps::ContextUpdate#scene_update_evaluator` | Single sentence player-facing status, written alongside the combat write in the same fan-out call. |
| `adventure_narrative_facts` | `Steps::Loremaster` (via `Lore::ApplyResults`) | Durable facts, both seed (`Lore::ExtractFromPremise` at story save) and per-turn (Loremaster in the output fan-out). Both call `Lore::ApplyResults`, which is the actual single insert seam. |
| `adventure_npcs` | `Lore::ApplyNpcs` | NPC creation and updates flow through Loremaster's NPC mutations only. |
| `adventure_locations` | `Lore::ApplyLocations` | Location creation and `(x, y)` placement via deterministic Vogel-spiral seeding (`Maps::PlaceLocations`). |

**Why the principle exists:** before the principle was enforced, multiple
steps wrote to the same JSONB blob with different assumptions about what
the existing value contained. ContextUpdate would carry an NPC forward;
Embellisher would overwrite the same key with a different NPC shape;
Warmaster would write a third shape to the same column on combat
initialization. The only way to keep these in sync was implicit
agreement, and it constantly broke. Naming a single writer per store
makes the contract explicit and reviewable: any change to a store's
shape is one diff in one file.

**Documented exception (Path A encounter pause):**
`DungeonMaster::EncounterWarmasterBridge` calls
`Utilities::Warmaster.persist_pending_combat!` when encounter combat is
spawned but initiative is still pending. This writes an NPC-only pending
roster to `combat_context` before ContextUpdate runs, so pause-time
state does not fall back to stale ended-combat snapshots. ContextUpdate
remains the sole writer on the resolved-combat path; the pending-pause
write is bounded to that one call site.

**Runs before every player-facing message:** ContextUpdate executes before
any pipeline early return that presents a message to the player —
including initiative prompts and roll requests, not only after full
narrative resolution. This ensures combat state is current at every
pause point.

**Combat context schema:** the formal field description for `combat_context`
lives in `app/services/dungeon_master/templates/schemas/contexts/combat.json`
and is injected into the ContextUpdate prompt via
`PromptRenderer.load_schema`.

**Context snapshots on AdventureLoop:** after each ContextUpdate run, the
combat snapshot is written to `adventure_loop.data["context_snapshot"]`.
This creates a debug trail without consuming AI context window — the
snapshot is in the database but never re-sent to the model.

### 19. Travel tracking through the pipeline

**Decision:** the pipeline tracks the player's location across three
steps:

1. **RollRequest** emits a `destination` field plus a `mechanical_summary`
   so when the player heads somewhere known, the request names the
   destination and the rules retrieved into the prompt cover overland
   movement (speed, mount, terrain, forced march).
2. **Mechanic verdict**: `mutations.travel`
   (`{ hours_traveled, distance_covered, new_location }`) captures the
   mechanical travel outcome alongside HP / condition mutations.
3. **`adventures.current_location_id`** is updated by the resolver from
   `travel.new_location`, resolving the destination name to an
   `adventure_locations` row. Loremaster reads facts about the new
   location on the next turn via `Lore::LocationsLookup`.

**Why:** without this chain, travel was a "gap" — the evaluation asked
for Constitution checks (forced march fatigue) but never computed how
far the player travelled, and downstream prompts saw a stale location.
Naming `current_location_id` as the canonical pointer keeps the world
state and the narrative aligned: any retrieval that needs nearby NPCs
or location facts queries by `current_location_id`, not by recovering
text from a JSON blob.

**Trade-off accepted:** the travel estimate is approximate — the model
computes an estimate based on rules of thumb (light horse ~48 mi/day on
road), not a precise simulation. This is acceptable because the DM
narrative is inherently approximate about distances; the key requirement
is that *relative position updates* (closer, arrived, departed) are
mechanically tracked rather than left to creative interpretation.

### 20. Purpose-based classification

**Decision:** the Classify step categorizes actions by their **purpose**,
not by the surface mechanics involved. Casting a utility spell (Mount,
Mage Armor, Fly) outside active combat is NOT classified as `combat` — it
is classified based on what the spell enables (e.g., `traversal` for
Mount).

**Why:** misclassifying "I cast Mount and ride to the village" as `combat`
caused a wasted evaluation iteration for a non-existent combat context and
skewed downstream steps. The classification should answer "what is the
player trying to accomplish?" not "does this involve spellcasting?"

### 21. Combat math is clamped at the receiving seam

**Decision:** the combat free-text path (`Steps::CombatRollRequest`) asks
the model only for a structured roll choice — the type, the `attack_option_id`
or `dc_formula`, and audit metadata. DCs and damage are computed in Ruby by
`Phases::CombatMechanicResolution`, which clamps the AI's choice against the
live attack options and live battlefield (defense kind, AC / touch AC /
flat-footed AC, save DCs, source weapon, damage dice).

**Why:** combat math is the canonical example of "code for certainty" (see
Design Philosophy §1). The AI is only the mouthpiece that picks which legal
option the player is using; the bounds and the math are owned by the sheet
and the grid.

**How:** the prompt template `combat_roll_request` lists legal attack options
the player has *right now* (resolved deterministically before the call), the
action economy snapshot, AoO threats, and the battlefield slice. The AI
returns an `attack_option_id` (never a DC) for an `attack_roll`, or a
`dc_formula` (`spell_dc` / `ability_dc`) for a `saving_throw`. Code resolves
the rest:
- `attack_option_id` → `AttackOptionBuilder.resolve_option_id!` → attack
  mode, defense kind, source type/id, damage dice, damage type.
- `defense_kind` + target → `WorldTurn::ParticipantLookup.defense_dc_for_target!`.
- `dc_formula` → `resolve_spell_dc` / `resolve_ability_dc` against the
  caster's sheet.

Resolution errors raise `CombatMechanicResolutionError` and fail the combat
free-text path closed rather than silently degrading.

**Signature ownership note (readability refactor):**
- `CombatMechanicResolution` carries a small `CombatResolutionContext` value
  object and forwards participant targeting through
  `WorldTurn::ParticipantLookup::LookupContext` instead of threading multiple
  `combat_ctx` / `sheet` / `adventure` keyword arguments through each helper.
- `Utilities::Warmaster` entrypoints accept explicit request objects
  (`EncounterInitializationRequest`, `NamesPreparationRequest`,
  `CombatInitializationRequest`) so call sites pass one cohesive object per
  operation boundary rather than spreading utility construction arguments
  across pipeline layers.

**Why:** combat rolls need stricter structure than the generic prompt can
reliably provide. The AI now classifies *what kind* of combat roll is needed
(`defense_kind`, `spell_dc`, `ability_dc`, `attack_of_opportunity`), while
Ruby resolves the numeric DC from live participant sheets. Non-combat domains
still benefit from lightweight instruction partials without needing this extra
normalization step.

**Domains covered by generic partials:** `traversal`, `social`,
`exploration`, `rest`, `inventory`, `buff`.

### 22. Scene summary as player-facing status

**Decision:** ContextUpdate's `scene_update_evaluator` sub-prompt produces
a `scene_summary` — a single concise sentence (under 15 words) describing
the player's current situation. It is persisted on `adventures.scene_summary`
and displayed in the player-facing UI.

**Why:** narrative messages are long; the player needs a quick status
line ("Traveling by horseback toward the village.") for the sidebar
without scrolling chat. ContextUpdate runs after every turn and is the
natural seam to refresh this string.

**UI behavior:** all players see the scene summary. Admin users
additionally see a collapsible "Combat Context" debug section showing
the raw `combat_context` object when combat is active.

### 23. Player-visible roll explanations

**Decision:** when the pipeline pauses for player rolls, the roll request
message now contains the evaluation summaries as human-readable content
rather than the static placeholder "The DM awaits your rolls..."

**How:** `DungeonMaster::Rolls::RollExplanation.from_summaries` strips `[DOMAIN]`
prefixes from the mechanical evaluation summaries and joins them into a
paragraph. The summaries explain the mechanical reasoning behind the
requested rolls.

**Why:** players were confused by roll requests that appeared without
context (e.g., two identical-looking Constitution checks without
explanation). The evaluation summaries already contain the "why" — they
just weren't being shown.

### 24. Sanitize/Classify merged into Intake

**Decision (superseded):** The original design split Triage into two parallel
steps: Sanitize (security filter) and Classify (domain categorization). This
decision has been superseded.

**Current design:** Sanitize and Classify have been merged into a single
**Intake** step that handles:
- Security scoring (danger on 0-100 scale)
- dm_query detection (`is_dm_query` field)
- Context gap suggestion (`suggested_context`, `context_suggestion_reason`)

Intake runs as one call. The pipeline rejects if `danger_score >= danger_threshold`
(configurable in DmConfig). This gate fires before any expensive downstream calls.

### 25. Evaluation architecture history

The evaluation step has gone through four generations; the current
single-call RollRequest / CombatRollRequest path is the result of the
previous three teaching us where the cost was:

1. **Per-domain Ruby-thread chain (retired):** six parallel beacon calls
   → up to six sequential MechanicalEvaluation calls → up to six parallel
   RollQualifier calls. 8–14 OpenAI calls per turn, stressed the DB
   connection pool, frequent duplicate rolls.
2. **UnifiedEvaluation (retired):** one AI call covering all six domains.
   Removed concurrency pressure but coupled prompt size to total domain
   count and prevented per-domain model tuning.
3. **ParallelEvaluation (retired):** restored the 3-phase chain but
   offloaded concurrency to a Node.js microservice (`evaluator/`) via
   `Promise.all`. Recovered observability and per-step model selection
   at the cost of three serial round-trips.
4. **RollRequest / CombatRollRequest (current):** a single AI call backed
   by pgvector RAG. The prompt has no character block and no JSONB
   context dump. Out of combat → `Steps::RollRequest`; in combat
   free-text → `Steps::CombatRollRequest` with combat-aware context
   (attack options, action economy, AoO threats, battlefield text). Combat
   math (DCs, damage, defense kind) is clamped at the receiving seam by
   `Phases::CombatMechanicResolution` from the AI-emitted
   `attack_option_id` — see Decision 21.

The Node evaluator microservice still exists and is still used by
Stagehand (parallel narrate + context updates), the sanity gate, and
ContextUpdate fan-outs, but no longer for a per-domain evaluation chain.

### 25a. Cheap-model prompt policy: simplify, don't stack warnings

**Decision:** when prompt changes are needed for reliability on cheap models,
changes must simplify ownership and contracts rather than layering additional
negative instructions.

**Why:** additive warning prompts ("DO NOT X", "DO NOT Y", "ALSO DO NOT Z")
increase token noise and ambiguity. Small models fail more often when asked to
remember long exception lists. Reliability improves when prompts are narrowed:
remove responsibilities the step should not own, replace ambiguous rules with
single clear contracts, or split overloaded prompts.

**Rule of thumb:**
- If data is deterministic and already owned in code (HP, turn order, roster
  shape, state transitions), fix in code at that seam.
- If behavior is language interpretation owned by AI, simplify/replace the prompt
  contract instead of appending more prohibitions.

**Anti-pattern:** code that parses player text or AI prose to "repair" model
output. This violates Design Philosophy §15 and §17.

### 26. SanityChecker (capability + world consistency validation)

**Decision:** rename CapabilityGuardrail to SanityChecker and split it
into two sub-checks:

**A) Capability Check** — validates that the player possesses the spells,
feats, or items they reference. Runs on the mechanics path only. Two modes
via `guardrail_mode`:
- `"code"` (default): deterministic fuzzy-match against character sheet.
- `"ai"`: AI prompt for holistic validation.

**B) World Consistency Check** — validates that the entities, targets, or
objects the player references actually exist in the current scene. AI-only
step that normally runs ALWAYS (in the sanity gate on the mechanics path, or
standalone on the non-mechanics path). Receives `combat_context`,
`scene_summary`, `scene_history`, and the top-K retrieved NPCs / locations /
facts (`Lore::NpcsLookup` / `LocationsLookup` / `FactsLookup`).

**Optional bypass:** when the adventure's `skip_world_sanity_check` boolean
attribute is `true` (set at adventure creation via the toggle in the
adventure creation form), the world consistency check is skipped on **both**
paths. On the mechanics path, `run_sanity_gate_fan_out` (world + capability
in one Node `/fan_out` round-trip) is replaced by a direct
`run_capability_check` call. On the non-mechanics path the standalone
`run_world_consistency_check` call is bypassed entirely. The capability check
is unaffected and still runs.

**Why:** the capability check alone was insufficient. Players could
reference non-existent creatures, NPCs, or objects (e.g., "attack the
goblin" when no goblin exists) and the pipeline would process the action
as valid. The world consistency check closes this gap.

On the mechanics path both checks normally run in parallel (2 threads) —
zero added latency on the happy path. On the non-mechanics path, the world
check runs as a standalone AI call.

Both sub-checks fail open on errors to avoid blocking the player.

**Model note:** the World Consistency Check requires a capable model
(gpt-4o-mini or better). Unlike other steps, this one cannot be
effectively decomposed for budget models.

### 27. Stagehand as code-only synthesis step

**Decision:** make the Stagehand step a pure code step with no AI call.
It sits between Mechanic and the output phase (Narrate + ContextUpdate
+ Loremaster), packaging the verdict and dispatching the output fan-out.

**Why:** the original step was an AI call that duplicated work already
done by the Mechanic step. Both received roll results and produced
outcomes — the only difference was one was "factual" and one was
"mechanical." In practice, the model often contradicted itself. By
making Stagehand a code-only routing layer, we eliminate the redundancy
and guarantee consistency.

### 28. Narration runs the output phase in parallel

**Decision:** Narrate, ContextUpdate (combat-only), and Loremaster all
run concurrently inside one evaluator fan-out (Node `Promise.all`). The
fan-out shape is fixed; there is no serial alternative.

**Why:** the three writers are independent — Narrate consumes the
verdict outcome, ContextUpdate consumes the combat mutations, and
Loremaster consumes the verdict outcome plus retrieved facts. Running
them in parallel saves two full LLM round-trips of latency on the
critical path. The single-mode approach also removes a historical
"subjugated" toggle that no user flipped, and it lets Loremaster's
zero-latency placement (Decision 37) rely on the fan-out
unconditionally.

### 29. Context updates receive factual outcomes, not narrative

**Decision:** the Micro Context Update step receives a factual outcome
summary (`what_happened`) and structured mutations rather than the
narrative text that the player sees.

**Why:** narrative prose is stylized, embellished, and sometimes
metaphorical. A context update model reading "the goblin's crimson ichor
stains the sacred stones" might not reliably extract that Goblin A took
8 damage and is now at 4 HP. By passing the factual outcome ("Player
hit Goblin A for 8 damage, Goblin A now at 4 HP, position unchanged")
and the structured mutations hash, the context update model works from
unambiguous data.

This also decouples context updates from narration — in parallel mode,
context updates don't need to wait for narration to complete.

### 30. *(retired — Social Scene Expansion)*

The Social Expander step was removed alongside the Momentum step. Social
interactions now resolve through the unified Mechanic path (no-roll
verdicts for "I greet the innkeeper", normal verdicts for skill-based
exchanges). Loremaster captures the durable result as facts. The
historical `expand_scene` signal on RollRequest is gone.

### 31. Roll deduplication removed (Principle 17)

**Decision:** remove `deduplicate_rolls!` — the code-side post-merge
deduplication that pattern-matched `[skill, type, dc]` on AI-generated
output to remove duplicate rolls.

**Why:** the dedup was a heuristic fix for an AI-generated problem. When
the legacy multi-domain MechEval produced duplicate Diplomacy DC 10 checks
from two different domain evaluations, code silently removed one. This
violated Design Philosophy Principle 17: code must not heuristically fix
AI problems.

**Current status:** RollRequest / CombatRollRequest are single-call and
emit at most one roll, so cross-domain duplicates are no longer a structural
risk. The dedup pass (`Rolls::PlayerRolls.deduplicate_rolls!`) is still
called on the merged result for defensive observability — if the model
emits two equivalent rolls, the warning surfaces in play_log; nothing is
silently rewritten.

**What stays:** `filter_auto_success_rolls!` is deterministic — it uses
real character sheet modifiers to identify rolls that are mathematically
impossible to fail. This is Principle 1 (code for certainty), not
Principle 17's anti-pattern.

### 32. StepRegistry as single registration point

**Decision:** consolidate the four separate constants that every new AI
step required updating (`AiLog::CALL_TYPES`, `DmConfig::TOKEN_BUDGET_STEPS`,
`DmConfig::STEP_MODEL_HINTS`, `DmConfig::DEFAULTS["token_budgets"]`) into
a single `DungeonMaster::StepRegistry` module.

**Why:** every new AI step (social expansion, creature generation, etc.)
required editing 4 constants across 2 files. Missing one caused silent
billing gaps, broken admin UI, or validation errors. The registry defines
each step once with its token budget, model hint, and pipeline flag. The
four constants now derive from it automatically.

**How to add a new step:** add one entry to `StepRegistry::STEPS` in
`app/services/dungeon_master/step_registry.rb`. Set `pipeline: true` for
DM pipeline steps (appears in admin config UI) or `pipeline: false` for
support services (enricher, embellisher — logged but not configurable).

**AiLog validation:** changed from strict rejection to warn-and-save.
Unknown `call_type` values are logged with a warning but the record is
always saved. This ensures AI costs are never lost due to a typo or
unregistered step — the warning makes the gap visible for correction.

### 33. PlayerInterpreter removed

**Decision:** remove the PlayerInterpreter step. Sanitized player input now passes
directly from Intake (or Sequencer) to the evaluation step.

**Why:** PlayerInterpreter's only job was producing a "pure restatement" of the
already-sanitized input — one AI call to rephrase what Intake had already cleaned.
The downstream evaluation step receives that input and does the real interpretive
work itself (domain classification, mechanics detection, rules routing). The
restatement added latency with no observable quality improvement. The step was
pure overhead.

**Trade-off accepted:** beacons now receive the sanitized input verbatim rather than
a semantically normalized restatement. In practice these are nearly identical;
Intake's sanitization already handles the safety and formatting concerns that
PlayerInterpreter was nominally addressing.

### 34. JSON response schemas as separate files

**Decision:** extract the expected JSON response format for each AI step into
standalone `.json` files under `templates/schemas/<step_name>.json`. The schema
file is loaded by `PromptRenderer.load_schema` and injected into the prompt
template via a local variable (`<%= @response_schema %>`), replacing inline JSON
examples that were previously hardcoded in the ERB template.

**Why:** inline JSON schemas in prompt templates had several problems:

- The schema was duplicated across the template (prompt instruction) and the Ruby
  parser (response handling) with no shared source of truth.
- Prompt templates became long and noisy — the JSON example often dwarfed the
  actual instructional prose.
- Schema changes required editing deeply nested ERB, increasing the risk of
  introducing malformed JSON that only surfaces at runtime.

Separate `.json` files are syntax-checked by editors and CI, are easy to diff,
and serve as canonical documentation for each step's contract.

**Convention:** schema files contain the full expected response structure with
descriptive placeholder values. Array entry shapes are documented under a
top-level `_entry_schemas` key (prefixed with `_` to signal metadata). The
prompt template instructs the model not to include `_entry_schemas` in its
response.

**Migration:** the pattern was first introduced with `unified_evaluation.json` (now removed along with the step itself). All remaining steps use their own schema files.

### 35. take_10 / take_20: AI decides eligibility, code computes the value

**Decision:** RollRequest / CombatRollRequest emit `take_10_eligible` and
`take_20_eligible` per roll based on prompt context (immediate-threat,
freely-retriable). The numeric `take_10_value` / `take_20_value` are then
computed in Ruby from the character sheet's skill modifier via
`Rolls::PlayerRolls.compute_take_values!`.

**Why:** the contract is split along the AI/code seam (Design Philosophy §1).
Eligibility is judgment that depends on the scene (any nearby threats? free
retries?) — natural fit for the AI. The numeric value is `10 + mod` or
`20 + mod`, where `mod` lives on the sheet's `derived_stats.skills`. No
reason to ask the model for arithmetic it cannot improve on.

### 36. `AdventureLoop#pipeline_outcome` as the authoritative narration seed

**Decision:** every `AdventureLoopResolution` terminal writes the action's narration seed into
`AdventureLoop#data["pipeline_outcome"]` via `batch_update!`. The narrative phase
(`run_accumulated_narrative_phase`) assembles the combined seed by querying all
`AdventureLoop` rows for the current `registry_entry_uuid` in `sequence_index` order
and joining their `pipeline_outcome` values with `"\n\nThen: "`. The old
`narrate_seed` field is removed from result hashes and from `AdventureMessage`
metadata entirely.

**Why:** the previous design threaded `narrate_seed` through every in-memory result
hash and carried `prior_narrate_seeds` across pause boundaries (serialised into
`roll_request` / `initiative_request` metadata). This created several problems:

- Encounter paths (non-combat and social scenes) could produce a nil seed when
  `verdict_outcome` was never set, causing `narrate.rb` to raise immediately.
- The pause/resume boundary required explicitly carrying seeds forward across
  the DB serialisation — a fragile contract where any missed key meant lost
  context.
- Context updates between compound actions read `result[:narrate_seed]`, which
  was nil for every terminal that didn't manually populate it.

`AdventureLoop` rows are already created for each action in a pipeline run and
indexed on `registry_entry_uuid`. Querying them adds one cheap indexed read and
replaces the entire in-memory accumulation pattern. Any terminal that writes to
the row automatically participates in the combined seed without changes to the
caller.

**Mapping of terminals to `pipeline_outcome`:**

| Path | Value written |
|---|---|
| Mechanic verdict (with or without rolls) | `verdict_result[:outcome]` — written by `finish_resolution` |
| Encounter — awaiting initiative | `[encounter_scene, verdict_outcome].compact.join("\n\n")` |
| Encounter — non-combat | same combined join |

---

### 37. Loremaster and the narrative facts store

**Decision:** durable narrative state lives in
`adventure_narrative_facts` — a per-adventure pgvector table
(`neighbor` gem, HNSW on `embedding vector(1536)`,
`text-embedding-3-small`). Steps that need plot-state context (Sanity
Checker's world consistency check, `Steps::Stagehand`'s outcome-keyed
retrieval that feeds Narrate) query this table by cosine similarity
against the player's intent or the verdict outcome. The sole writer is
the **Loremaster** AI step.

**Placement.** Loremaster runs in the output-phase fan-out alongside
Narrate and ContextUpdate. The LLM call fits inside the Narrate latency
window — it does not add a sequential step to the critical path.

**Seed path — story authoring.** Seed facts are produced once at story
save time, not at adventure creation. `Lore::ExtractFromPremise` reads
`Story.premise` (the spoiler-bearing full plot) and
`Story.opening_message` (the player-facing first scene) and emits a
list of `seed_facts` persisted on the Story. At adventure creation,
`Adventures::Bootstrap` bulk-inserts those rows into
`adventure_narrative_facts` with `source: "seed"` and
`introduced_at_loop_id: nil`. Turn 1's retrieval is therefore not a
cold start.

Seed and turn rows go through the same `Lore::ApplyResults` insert
seam, so they are indistinguishable downstream except by the `source`
column.

**Two embeddings round-trips per turn, independent of fact count.**
`Lore::FactsLookup` embeds the intent once at the sanity gate (read
side); `Lore::ApplyResults` makes **one batched** `AiClient#embeddings`
call for all Loremaster-emitted fact texts after the fan-out returns
(write side). Both call sites own their own `AiLog` rows
(`call_type: "embedding"`) — `AiClient` stays HTTP-and-retry-only,
matching the rest of the repo.

**Lossy-with-Sentry contract.** Loremaster writes are best-effort: no
transaction wraps them; the Mechanic verdict and ContextUpdate combat
write commit independently and earlier in the turn regardless of
Loremaster's outcome. **Every** failure — AI error, JSON parse error,
per-row insert error, seeding failure — is reported through
`@log.report_error` (→ `ApplicationErrorReporter` → Sentry) **before**
any `loremaster_failure` or `seed_failure` play_log event. Per
[.cursor/rules/error-reporting-sentry.mdc](../.cursor/rules/error-reporting-sentry.mdc)
this is non-negotiable: the data is allowed to be lossy, the error
signal is not. A partial unique index on
`(adventure_id, introduced_at_loop_id, source_idx) WHERE source = 'loremaster'`
makes accidental reapply a no-op instead of a duplicate, so higher-layer
retries stay idempotent under the lossy contract.

**Intra-queue staleness is accepted.** In a multi-action player message
("pick up the rope, then throw it across the chasm"), Loremaster runs
exactly once — in the terminal narrative phase after the last action —
and Action 2's retrieval reads the fact set that was live at the start
of the player message. Inter-action Loremaster invocations were rejected
as triple-the-call-volume for negligible gain.

**Fact kinds.** Loremaster's output contract covers three kinds:
- `event` — something that happened future actions must remain consistent
  with ("the bridge collapsed").
- `state` — a current condition that constrains what the player can
  attempt ("the party is in the middle of the ocean"). State is replaced
  via invalidation: when it changes, Loremaster emits the new state fact
  AND an `invalidates` entry referencing the old fact's id, paired via
  `replacement_source_idx`. Rails dereferences that into
  `invalidated_by_fact_id` at apply time.
- `entity` — an NPC, object, or location the narrative introduced ("the
  innkeeper is named Gerta"). Entity facts are paired with
  `Lore::ApplyNpcs` / `Lore::ApplyLocations` writes when the AI also
  emits structured NPC or location records (see §2 for the per-store
  ownership table).

---

## Step Index

For flow and behavioral detail see [pipeline_diagram.md](pipeline_diagram.md). Source files below.

| # | Step | Type | Source |
|---|------|------|--------|
| — | **`#run_prompt` outer phases** | Code (orchestration) | `app/services/dungeon_master/pipeline_engine/concerns/entry_points.rb`, `app/services/dungeon_master/pipeline_engine/phases/*.rb` |
| — | **`ActionQueueRunner`** | Code (queued actions) | `app/services/dungeon_master/pipeline_engine/action_queue_runner.rb` |
| 0 | **Moderation gate** | Code + Node evaluator `POST /moderate` | `app/services/dungeon_master/moderation_service.rb`, `app/jobs/moderation_check_job.rb`, `evaluator/src/index.js` |
| 1 | **Intake** | AI | `app/services/dungeon_master/steps/intake.rb` |
| 1c | **DM Query** | AI (fast path) | `app/services/dungeon_master/steps/dm_query.rb` |
| 1d | **Sequencer** | AI (toggled) | `app/services/dungeon_master/steps/sequencer.rb` |
| -- | **AdventureLoopResolution** (module) | Code orchestration | `app/services/dungeon_master/adventure_loop_resolution.rb` |
| 3 | **RollRequest** | AI ×1 (out of combat) | `app/services/dungeon_master/steps/roll_request.rb` + `templates/roll_request.text.erb` |
| 3′ | **CombatRollRequest** | AI ×1 (combat-active free-text) | `app/services/dungeon_master/steps/combat_roll_request.rb` + `templates/combat_roll_request.text.erb` + `Phases::CombatMechanicResolution` (post-call clamping) |
| 4 | **SanityChecker** | AI (parallel, mechanical path) | `app/services/dungeon_master/steps/sanity_checker.rb` |
| 5 | **Mechanic** | AI (mechanical path, non-combat or inactive combat) | `app/services/dungeon_master/steps/mechanic.rb` |
| 5′ | **Combat GM** | AI (mechanical path, **active combat** — `combat_active?`) | `app/services/dungeon_master/steps/combat_gm.rb`, `templates/combat_gm.text.erb` |
| 5a.5 | **World Turn** | Code orchestration | `app/services/dungeon_master/steps/world_turn.rb`, `app/services/dungeon_master/world_turn/*.rb` |
| 5a.5-i | **↳ npc_action** | AI ×N (parallel `/fan_out`; code applies sequentially) | `app/services/dungeon_master/steps/world_turn.rb`, `app/services/dungeon_master/world_turn/npc_action_prompt.rb` |
| 5b | **TimeKeeper** | Code-first, AI fallback | `app/services/dungeon_master/steps/time_keeper.rb` |
| -- | **Harbinger** (utility) | Code + optional AI | `app/services/dungeon_master/utilities/harbinger.rb` |
| -- | **Warmaster** (utility) | Code + optional AI | `app/services/dungeon_master/utilities/warmaster.rb` |
| -- | **GameClock** (utility) | Code-only | `app/services/dungeon_master/utilities/game_clock.rb` |
| 6 | **Stagehand** | Code-only | `app/services/dungeon_master/steps/stagehand.rb` |
| 7 | **Narrate** | AI | `app/services/dungeon_master/steps/narrate.rb` |
| 8a | **ContextUpdate** (combat + scene_summary) | AI (parallel with 7/8b) | `app/services/dungeon_master/steps/context_update.rb` |
| 8b | **Loremaster** | AI (parallel with 7/8a in the output-phase fan-out) — sole writer of `adventure_narrative_facts` (see Decision 37) | `app/services/dungeon_master/steps/loremaster.rb`, `app/services/dungeon_master/lore/apply_results.rb`, `app/services/dungeon_master/lore/extract_from_premise.rb`, `app/services/dungeon_master/lore/facts_lookup.rb` |
| -- | **Mutations** | App-side | `app/services/dungeon_master/mutations.rb` |

**Action queue narrative delivery modes:** when `action_queue` is not `false`, the Sequencer splits input into multiple actions. There are two progressive modes:

- **`"progressive"` (default):** each resolved action is narrated immediately via `run_single_action_narrative_phase` and broadcast as a `pipeline_action_result` WebSocket event before the next action begins. The pipeline returns `:narrated_sequence`. No prior action context is injected into evaluation or narration.
- **`"progressive_continuity"`:** same streaming behaviour, plus prior action `pipeline_outcome` values are read from `AdventureLoop` and injected into the narrate prompt so each action is narrated with awareness of what earlier actions in the same turn produced.

Interrupted queues (encounter, social scene, roll request) fall back to the accumulated path for the interrupting event regardless of mode.

## What is AI vs. what is code

| Component | AI? | Notes |
|---|---|---|
| RollRequest | ✅ AI ×1 | Out-of-combat single call. Top-K rules + scene beats from pgvector; no character block. Emits one roll spec or "no roll" plus cross-cutting signals (affected_contexts, expand_scene, transition, combatants, destination) |
| CombatRollRequest | ✅ AI ×1 + ❌ code clamping (`Phases::CombatMechanicResolution`) | Combat-active free-text. Carries attack options, action economy, threats, battlefield text. Emits `attack_option_id` (never DC) for combat rolls; Ruby resolves attack mode, defense kind, damage metadata, and AC / save DCs from the sheet |
| Mechanic | ✅ AI | Post-roll arbitration + structured mutations when combat is not active. No-roll actions resolve through this same step with `rolls: []`. |
| Combat GM | ✅ AI | Post-roll arbitration during **active combat** (battlefield slice + PF1e combat guidance); emits `battlefield_patches` + `action_economy_delta` |
| World Turn (orchestration) | ❌ Code | Shared-snapshot NPC turn orchestration, sequential dice + mutation application in initiative order, combat advancement, and combat-end handling |
| NPC Action (individual decisions) | ✅ AI ×N | One Node `/fan_out` batch (parallel AI) against the same live combat snapshot; code resolves and applies per NPC in order |
| TimeKeeper (journey / combat / rest / take_20) | ❌ Code | Deterministic formulas |
| TimeKeeper (fallback freeform estimate) | ✅ AI | Used only when no code rule applies |
| Harbinger / GameClock / Warmaster turn ordering | ❌ Code | Encounter math, clock math, and deterministic combat state transitions |
| Narrate / ContextUpdate / Loremaster | ✅ AI | Prose, combat-context writing, and durable-fact extraction; all run in one output-phase fan-out |

### 5. World Turn after player resolution in active combat

**Decision:** after a player's action resolves in active combat, the pipeline runs a
code-owned **World Turn** phase before narration. World Turn computes which NPCs
act, asks all acting NPCs what they do from the same live combat snapshot (one
parallel `/fan_out`), then applies dice and mutations **in initiative order** in
code (stopping early if the player dies, is incapacitated, or combat ends), and
emits deterministic `combat_state_advancement` for ContextUpdate to write.

**Why:** the previous combat flow treated combat like any other action: one
player message in, one outcome out. That left three correctness gaps:

- NPCs never took proper initiative-ordered turns
- `current_turn` / `round` advancement depended on AI inference from prose
- player-facing damage from NPC turns had no deterministic owner

World Turn fixes that by separating **combat orchestration** from **individual NPC
judgment**. Code decides who acts and when; AI decides what a given NPC tries to
do on its turn.

**Why NPC actions are parallelized from one shared snapshot:** the desired combat
model is that all NPCs choose their actions for the round "at once" with respect
to AI judgment, then code resolves the resulting dice and mutations. This keeps
the Node `/fan_out` latency win (one batch instead of N sequential evaluator
round-trips).

**Trade-off accepted:** NPC prompts do not see each other's *chosen* actions—only
the shared pre-turn snapshot. Code still applies outcomes in initiative order and
stops applying further NPC consequences if combat ends or the player is
dead/incapacitated mid-round, so later NPCs do not keep damaging a resolved
encounter.

When `instant_death` is disabled, World Turn also owns PF1e-style dying bleed-out:
code applies the per-round HP loss and stabilization check before NPC fan-out,
and can mark `player_death` / close combat without waiting for AI to infer it.

---

## Error Handling

All AI steps follow the same error handling pattern:

1. **`TokenBudgetExceededError`**: raised by `AiClient` when the API
   returns `finish_reason: length`. This is a hard error for critical
   steps -- even truncated non-empty responses are rejected. The error is
   logged with `status: "token_budget_exceeded"` and re-raised (for
   intake, roll_request, combat_roll_request, mechanic, narrate) or
   swallowed with an empty result (for ContextUpdate, Loremaster, and
   the capability guardrail, which are non-critical).

2. **`AiError`**: covers API unreachability, malformed responses, and
   other failures. Same re-raise/swallow pattern as above.

3. **Node `/fan_out` resilience**: Node returns 5xx with `{ error, partial_results }` on any fan-out failure (used by Stagehand, the sanity gate, ContextUpdate). Rails persists logs for completed calls from `partial_results` before raising `AiError`. All-or-nothing per phase — partial data is never used to proceed.

4. **Context update resilience**: Steps 8a and 8b rescue all errors and
   return empty hashes rather than failing the pipeline. A failed context
   update degrades future prompts but doesn't break the current turn.

5. **SanityChecker resilience**: both capability check and world consistency
   check fail open on errors, preventing validation system failures
   from blocking the player.

At the service level, all errors are caught and translated into a
generic player-facing message: *"The Dungeon Master is momentarily
distracted..."*. Technical details are logged only.

---

## Logging

Every AI call produces an `AiLog` record containing:

| Field | Description |
|---|---|
| `step` | Pipeline step name (intake, sequencer, roll_request, combat_roll_request, sanity_checker, sanity_checker_world, mechanic, combat_gm, time_keeper, narrate, combat_narrator, context_update, loremaster, npc_action). Historical step names (momentum, social_expansion, chronicler, micro_context_update, macro_narrative_update, enricher, embellisher) still appear in older `AiLog` rows. |
| `prompt_summary` | Truncated description of what was asked |
| `raw_response` | The complete API response |
| `parsed_response` | The parsed JSON |
| `parse_status` | Whether parsing succeeded, used fallback, etc. |
| `request_body` | The full request (system prompt + user message) |
| `model_used` | Which model actually processed this call |
| `status` | Success, error, or `token_budget_exceeded` |
| `reasoning` | Extracted from the AI's `reasoning` field (when present) |

This makes every pipeline execution fully auditable. The `model_used`
field is especially important with per-step model selection -- it records
exactly which model was used, not just which was configured.

---

## Encounter-to-Combat Lifecycle

When combat starts, the pipeline must transition from narrative flow to
mechanical combat state. This is handled by the **Warmaster** utility
through two entry paths:

### Path A — Harbinger-triggered encounter

```
TimeKeeper → Harbinger (roll encounter) → encounter_entry found
  → AdventureLoopResolution#dispatch_encounter_warmaster
    → EncounterWarmasterBridge.call → Warmaster.initialize_from_encounter!
      → spawn creatures (manifest or fuzzy bestiary + dynamic fallback)
      → roll creature initiative
      → return :awaiting_initiative
  → Pipeline pauses, sends initiative_request to player
```

### Path B — Narrative-originated combat

```
RollRequest → transition: "combat_started", combatants: [...]
  → Stagehand#maybe_initialize_combat
    → Warmaster.initialize_from_names!
      → fuzzy bestiary lookup + dynamic fallback
      → roll creature initiative
      → return :awaiting_initiative
  → Pipeline pauses, sends initiative_request to player
```

### Initiative Resolution

1. Player submits initiative → `finalize_combat!` → `combat_context` populated → pipeline continues
2. Player ignores prompt and sends new action → `DungeonMaster::Rolls::AdventureMechanicalState.auto_finalize_pending_initiative!` →
   auto-roll (d20 + DEX mod) → `finalize_combat!` → new action processed in combat context

### Guards

- `combat_active?` check in `TimeKeeper#consult_harbinger_if_needed` prevents encounters during combat
- `stagehand_combat_active?` check prevents re-initialization when combat is already active
- Combat-active turns are routed to `Steps::CombatRollRequest` rather than `Steps::RollRequest`, so the `combat_started` transition signal is structurally not available mid-combat

### Creature Resolution Chain

1. **Manifest** (if `EncounterTableEntry#has_manifest?`): deterministic bestiary lookup by ID
2. **Fuzzy bestiary match**: singularize → exact LOWER → ILIKE → id fallback
3. **Dynamic fallback** (per `creature_creation_fallback` config):
   - `"ai"`: AI generates PF1e stat block via `creature_generation` step
   - `"template"`: tier-scaled generic stat block
   - `"none"`: creature not created

See `app/services/dungeon_master/utilities/warmaster.rb` for implementation detail.

---

## Abandoned Pipeline Detection

When a player sends a new message while a previous pipeline is waiting for
rolls or initiative, the service layer logs the abandonment via `DmLog`:

```
"Previous pipeline abandoned (roll_request): player sent new input.
 Original intent: I cast fireball at the goblin"
```

This is visible in the admin pipeline logs for diagnostic purposes.

---

## Configuration

### Moderation config (`config/moderation.yml`)

Loaded at boot from the YAML file — changes require a redeploy. Not editable via the admin UI.

| Setting | Default | Description |
|---|---|---|
| `moderation.enabled` | `true` | Master switch. When `false`, the moderation gate is skipped entirely for all users. |
| `moderation.max_strikes` | `3` | Number of offenses before a user is automatically banned. Trusted users who hit this threshold also lose their trusted status. |
| `moderation.default_response` | _(see file)_ | In-world flavour text returned to a non-trusted user when their input is flagged. Shown as a DM message without starting a pipeline run. |

### DmConfig settings (admin UI — `/admin/dm_config`)

All pipeline behavior is configurable through `DmConfig` (admin UI at
`/admin/dm_config`):

| Setting | Default | Affects |
|---|---|---|
| `danger_threshold` | `30` | Intake: danger score cutoff (0-100) |
| `verbose` | `false` | Narrate: enables unconstrained response length |
| `pacing_words_min` | `40` | Narrate: minimum word count target when verbose is off |
| `pacing_words_max` | `120` | Narrate: maximum word count target when verbose is off |
| `temperature` | `0.8` | All steps: creativity/randomness (non-reasoning models only) |
| `model` | `gpt-4o-mini` | Default model for all steps |
| `step_models[step]` | `{}` | Per-step model override |
| `token_budgets[step]` | `nil` (no limit) | Per-step max completion tokens - defaults to no limit; set specific values only as safety kill switches |
| `action_queue` | `"progressive"` | Controls action splitting and narrative delivery. `false` — no splitting; `"progressive"` — split compound inputs, stream each action's narrative immediately via `pipeline_action_result` WebSocket events; `"progressive_continuity"` — as progressive, plus each action is narrated with prior action outcomes from `AdventureLoop` injected into the narrate prompt. Per-adventure override: `dm_settings["action_queue"]`. |
| `guardrail_mode` | `"code"` | `"code"` (deterministic) or `"ai"` (prompt-based) |
| `creature_creation_fallback` | `"ai"` | `"ai"` (bestiary + AI gen), `"template"` (bestiary + generic stats), `"none"` |
| `scene_history_depth` | `10` | Number of scene summaries retained for world consistency checks |
| `skip_world_sanity_check` _(per-adventure attribute)_ | `false` | Per-adventure toggle set at creation time. When on, the world consistency check is bypassed on both the mechanical and non-mechanical resolution paths. The capability check always runs. |

### Token budget configuration

All pipeline steps now default to **no token limits** (unlimited tokens). Token budgets are safety kill switches, not AI guidance - they prevent runaway costs but do not constrain model behavior.

**Leave budget fields blank for no limits (recommended)**. Only set specific token limits if you need cost protection for a particular step.

Previously, steps had specific default budgets, but these have been removed to allow unlimited token usage by default.

### Model tiers

Prices are **per 1 million tokens** (input / output).

**Nano — dirt-cheap, low latency.** Best for: classification, simple JSON, short-answer tasks.

| Model        | Input  | Output | Reasoning | Temp |
|--------------|--------|--------|-----------|------|
| gpt-4.1-nano | $0.10  | $0.40  | No        | Yes  |
| gpt-5-nano   | $0.05  | $0.40  | Yes       | No   |

**Mini — balanced cost/capability.** Best for: structured reasoning, moderate rule application, context updates.

| Model        | Input  | Output | Reasoning | Temp |
|--------------|--------|--------|-----------|------|
| gpt-4o-mini  | $0.15  | $0.60  | No        | Yes  |
| gpt-4.1-mini | $0.40  | $1.60  | No        | Yes  |
| gpt-5-mini   | $0.25  | $2.00  | Yes       | No   |
| o3-mini      | $1.10  | $4.40  | Yes       | No   |
| o4-mini      | $1.10  | $4.40  | Yes       | No   |

**Full — highest non-pro capability.** Best for: creative writing, complex multi-factor evaluation, narrative.

| Model   | Input  | Output  | Reasoning | Temp |
|---------|--------|---------|-----------|------|
| gpt-4o  | $2.50  | $10.00  | No        | Yes  |
| gpt-4.1 | $2.00  | $8.00   | No        | Yes  |
| gpt-5   | $1.25  | $10.00  | Yes       | No   |
| gpt-5.1 | $1.25  | $10.00  | Yes       | No   |
| gpt-5.2 | $1.75  | $14.00  | Yes       | No   |
| o3      | $2.00  | $8.00   | Yes       | No   |

**Pro — maximum compute (use sparingly).** A single turn could cost dollars. Only for offline batch analysis or debugging a gnarly ruling.

| Model       | Input   | Output   | Reasoning | Temp |
|-------------|---------|----------|-----------|------|
| gpt-5-pro   | $15.00  | $120.00  | Yes       | No   |
| gpt-5.2-pro | $21.00  | $168.00  | Yes       | No   |
| o3-pro      | $20.00  | $80.00   | Yes       | No   |
| o1-pro      | $150.00 | $600.00  | Yes       | No   |

**Legacy — avoid for new deployments.** Superseded by newer models that are cheaper and smarter.

| Model         | Input  | Output | Reasoning | Temp |
|---------------|--------|--------|-----------|------|
| gpt-4-turbo   | $10.00 | $30.00 | No        | Yes  |
| gpt-4         | $30.00 | $60.00 | No        | Yes  |
| gpt-3.5-turbo | $0.50  | $1.50  | No        | Yes  |
| o1            | $15.00 | $60.00 | Yes       | No   |
| o1-mini       | $1.10  | $4.40  | Yes       | No   |
