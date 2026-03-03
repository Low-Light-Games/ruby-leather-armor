# Dungeon Master Pipeline — Step Reference

Design document describing the AI Dungeon Master pipeline: what each step
does, what it receives, what it produces, and how the steps connect.

---

## Design Decisions

Architectural choices that shaped the pipeline, why each alternative was
rejected, and what trade-offs we accepted.

### 1. Sequential pipeline of small prompts vs. single monolithic prompt

**Decision:** break the AI interaction into focused calls instead of
one large "do everything" prompt. A single-call alternative (Edge Pipeline)
exists as a configurable opt-in mode.

**Why:** the original architecture used a single prompt that received the
player input, all context, all rules, and was expected to sanitize,
adjudicate, narrate, and update state in one pass. This had compounding
problems:

- **Accuracy degrades with task count.** When a model handles
  sanitization, classification, rules lookup, mechanical resolution,
  narrative writing, and context updates simultaneously, each sub-task
  gets less attention. Ruling accuracy suffered most — the model would
  skip attack-of-opportunity triggers or misapply grapple rules because
  it was also thinking about prose quality.
- **Token budgets are impossible to tune.** A single call needs a budget
  large enough for the worst case (long narration + complex multi-context
  ruling), wasting tokens on simple turns.
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

**Alternative preserved:** the Edge Pipeline (see below) collapses all
steps into one call, gated by `pipeline_mode: "edge"`. This is available
for low-traffic deployments or latency-sensitive scenarios where the
trade-offs are acceptable.

### 2. Six micro-contexts instead of a single context blob

**Decision:** maintain six separate JSONB context fields on the Adventure:
`traversal_context`, `combat_context`, `social_context`,
`exploration_context`, `rest_context`, and `inventory_context`, each with
its own schema.

**Why:** Pathfinder 1e naturally decomposes into these six gameplay
domains. A player action can affect multiple domains simultaneously ("I
jump into the sacred lake to escape my attackers" touches combat,
traversal, and social), and each domain has fundamentally different state
shapes:

- Combat: turn order, round number, participant HP, conditions, positions
- Traversal: location, terrain, weather, exits, nearby NPCs
- Social: NPC attitudes, conversation state, persuasion progress
- Exploration: searched areas, discovered items/secrets, active detection
- Rest: resting state, hours, watch order, spell preparation, recovery
- Inventory: recently acquired/used items, identifications, equipped gear

The original design used three contexts (combat, traversal, social). The
expansion to six came from observing that exploration ("I search the room
for traps"), rest ("I set up camp for the night"), and inventory ("I use
my Potion of Cure Light Wounds") are mechanically distinct domains with
their own rules, state shapes, and tracking needs. Folding them into the
original three produced awkward fits — "searching for traps" is not
really traversal, and "drinking a potion" is not combat.

A single blob would force the AI to reason about all six schemas in
every call, even when only one is relevant. Separate contexts let the
MechanicalEvaluation step receive *only the domain it's adjudicating*,
keeping the prompt focused and the output structured.

**Trade-off accepted:** the Context Update step must output relevant
contexts. This is mitigated by the selective context update optimization
(see Decision 18) — only affected and active contexts are sent to the
model.

**Alternative rejected:** a single `game_state` JSON blob was the initial
design. It produced inconsistent schemas (the model would invent different
field names across turns) and made it hard to scope the mechanical
evaluation to one domain.

### 3. App-side NPC roll resolution

**Decision:** the application rolls dice for NPCs using `rand(1..20)`,
not the AI.

**Why:** if the AI resolves NPC rolls, it can:
- Fudge results to fit a narrative it wants to tell
- Produce results that don't match the NPC's actual stat block
- Be inconsistent about which modifiers it applies

By having the app roll deterministically using the modifiers specified
by the MechanicalEvaluation step (which references real `CreatureSheet`
data), we guarantee that NPC combat is mechanically honest. The
MechanicalEvaluation step decides *what* the NPC does and *what modifier*
applies; the app decides *what the die shows*.

**Trade-off accepted:** the Ruling step receives NPC results as text
("Goblin A rolled 14 + 3 = 17 vs AC 15: HIT") rather than structured
data. This is slightly more work to parse but keeps the ruling prompt
human-readable.

**Player rolls are different:** the player submits their own roll results
via the UI. This is a deliberate engagement choice — rolling dice is part
of the tabletop experience. The app trusts the player's reported values
(honor system, as in a real tabletop game).

### 4. MechanicalEvaluation loop with summary chaining

**Decision:** run the MechanicalEvaluation step once per affected context,
passing previous evaluation summaries to each subsequent iteration.

**Why:** asking the AI to adjudicate combat mechanics, traversal skill
checks, and social consequences in a single prompt produces unreliable
results. The model loses track of which rules apply where — it might
apply combat attack-of-opportunity rules to a social interaction, or
forget a traversal check because it was focused on combat.

By looping with summaries, each call is scoped to one domain ("you are
adjudicating COMBAT only") while retaining cross-context awareness
("here's what already happened in TRAVERSAL"). The summary chaining
ensures that the social evaluation knows the player jumped into the sacred
lake (from the traversal evaluation) without having to reason about swim
checks itself.

**Trade-off accepted:** multi-context actions cost 2-3x the mechanical
evaluation budget. This is acceptable because multi-context actions are
less common than single-context ones, and the accuracy improvement is
dramatic.

**Alternative rejected:** forking the entire pipeline per context was
considered but would have duplicated ruling, narration, and context
updates — far more expensive and harder to merge into a coherent
narrative.

### 5. Ruling before narration (mechanics-first ordering)

**Decision:** determine the factual mechanical outcome before writing
any narrative.

**Why:** if the model narrates and evaluates simultaneously, narrative
bias corrupts mechanical accuracy. The model might write a dramatic
"the goblin collapses!" moment and then produce mutations showing the
goblin at 3 HP — or vice versa, produce correct mutations but a
narrative that contradicts them.

By ruling first, the Narrate step receives a factual outcome it must
faithfully narrate. It cannot contradict the mechanics because it didn't
determine them.

**Trade-off accepted:** two AI calls where one might suffice. The cost
is justified by correctness — mechanical errors in a Pathfinder game
(wrong HP, missed saves, ignored conditions) directly degrade the
player's trust in the DM.

### 6. Structured mutations instead of natural language

**Decision:** the Ruling step outputs explicit structured mutations
(`{ "hp_change": -8 }`) rather than prose ("the goblin takes 8 damage").

**Why:** the app must apply these changes to the database. If the AI
produces natural language, the app must parse it — "takes 8 damage",
"loses 8 hit points", "is dealt 8 points of damage" all mean the same
thing but require NLP to extract. Structured JSON is unambiguous and
directly actionable.

This also makes mutations auditable. Every `AiLog` entry for a `ruling`
step contains the exact mutations that were applied, traceable back to
the rolls and evaluations that produced them.

### 7. Rules fetched by slug from a YAML index

**Decision:** rules are stored as YAML files keyed by slug. The
InterpretationDispatcher step requests rules by slug, and the app
fetches the corresponding text to inject into the MechanicalEvaluation
prompt.

**Why:** LLMs hallucinate rules. Pathfinder 1e has thousands of rules
with subtle interactions (grapple, combat maneuvers, spell resistance,
damage reduction). If the model recites rules from memory, it will get
details wrong — particularly for less common rules.

By giving the model a manifest of available rules (slug + short
description) and having it request what it needs, we ensure:
- The MechanicalEvaluation step receives accurate rule text, not
  hallucinated rules
- The rules can be updated or corrected without retraining
- We can audit which rules were used for each evaluation

**Trade-off accepted:** the dispatcher step must correctly identify which
rules are relevant. If it misses a rule, the MechanicalEvaluation step
won't have it. This is mitigated by providing domain-scoped rule
manifests — each dispatcher sees rules relevant to its domain.

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

**Decision:** when Classify categorizes the input as `dm_query`, skip the
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

### 11. Pipeline class separated from the service

**Decision:** `DungeonMaster::Pipeline` encapsulates pure pipeline logic
(step sequencing, branching, data flow). `DungeonMasterService` handles
only message persistence and error handling.

**Why:** the original `DungeonMasterService` was a monolith that mixed
pipeline orchestration, message persistence, error handling, and step
implementations. Reading it required holding the entire flow in your head
to understand any single part.

The separation means:
- `Pipeline#run_prompt` reads like a linear script: sanitize + classify,
  then branch, then intent, then dispatchers, then mechanics gate, etc.
  A developer can read the full flow in ~40 lines.
- The service's `process_player_prompt` is equally clear: persist the
  player message, run the pipeline, map the result to messages, catch
  errors.
- Steps can be tested against the Pipeline without mocking persistence.

**Trade-off accepted:** more files to navigate. Mitigated by consistent
naming and the `DungeonMaster::Steps::*` module convention.

### 12. Per-step model selection

**Decision:** each pipeline step can use a different AI model, configured
via `DmConfig#model_for(step)` with a global default fallback.

**Why:** steps have fundamentally different cognitive demands:

- Sanitize and Classify are simple classification — a nano model handles
  them perfectly
- MechanicalEvaluation requires precise rule interpretation — benefits
  from reasoning models
- Narrate requires creative prose — benefits from large, temperature-
  tunable models
- Context Update is structured JSON — a mini model is plenty

A single model for all steps forces a choice between overpaying for
cheap steps or under-serving expensive ones. Per-step selection lets you
put the budget where it matters.

This also future-proofs for fine-tuning: steps with consistent schemas
(sanitize, classify, intent, dispatchers, context updates) are strong
fine-tuning candidates. You can fine-tune a cheap model on logged examples
and slot it in for one step without affecting others.

**Trade-off accepted:** more configuration complexity. The admin UI
mitigates this with per-step suggestions, model cost display, and
sensible defaults.

### 13. Reasoning field on all AI outputs

**Decision:** every pipeline step's JSON schema includes a `reasoning`
field that the model must populate.

**Why:** when something goes wrong (incorrect evaluation, bad ruling,
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
- A ruling with mutations missing NPC entries
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

**Decision:** the Micro Context Update and Macro Narrative Update steps
rescue all errors and return empty hashes instead of failing the pipeline.

**Why:** context updates are important but not critical to the current
turn. If the micro context update fails:
- The player still sees their narrative (it was generated before or
  alongside context updates)
- Future prompts may be slightly degraded (stale context) but still
  functional

Failing the entire turn because a context update errored would be
disproportionate — the player would see an error message for a turn that
was otherwise fully resolved and narrated.

The error is still logged, so the admin knows context updates are
failing and can investigate.

### 17. Parallel execution of independent steps

**Decision:** several step pairs run concurrently in Ruby threads:
- Sanitize + Classify (the gate)
- MechanicalEvaluation + CapabilityGuardrail (the mechanics gate)
- Narrate + ContextUpdate (the output phase, in parallel mode)
- Micro Context Update + Macro Narrative Update (within context updates)

**Why:** these pairs write to different data and have no dependencies on
each other's outputs. Running them in parallel saves one or more full AI
round-trips of latency per turn.

**Trade-off accepted:** Ruby thread complexity and database connection
pool pressure. Mitigated by wrapping all `Thread.new` blocks with
`ActiveRecord::Base.connection_pool.with_connection` to ensure proper
checkout and return. The connection pool is sized at 12 to accommodate
peak parallelism (~8 concurrent connections during dispatcher fan-out).

### 18. Selective context updates (affected + active only)

**Decision:** the Micro Context Update step only includes *relevant*
contexts in its prompt — those flagged as `affected_contexts` by the
dispatchers plus any that already contain data (active contexts). Contexts
that are both unaffected and empty are omitted entirely.

**Why:** with six context domains, sending all six to the model on every
turn wastes tokens and dilutes the model's attention. A pure social
interaction has no reason to include empty combat, rest, and inventory
contexts. By scoping the prompt to only what matters, we:

- Reduce prompt size (fewer input tokens billed)
- Reduce output size (the JSON schema only requests relevant keys)
- Focus the model on meaningful updates rather than copying empty objects
- Preserve cross-context coherence by including *active* contexts even
  when they weren't directly affected — e.g. an ongoing combat context
  is visible during a traversal action so the model can mark combat as
  ended if enemies were left behind

Contexts included in the prompt are labelled `[UPDATE]` (directly
affected) or `[maintain]` (active but not affected), giving the model
clear instructions on where to focus effort versus where to carry
forward the existing state.

**Fallback:** if no relevant contexts can be determined (e.g. the very
first turn of a new adventure where nothing has data yet), all six
contexts are sent so the model can initialize whichever ones apply.

**Trade-off accepted:** a context that is both empty and unaffected
will not be initialized by this step. This is correct behavior — if the
player hasn't done anything that touches combat, there shouldn't be a
combat context yet. The context will be created naturally when the player
first engages that domain.

**Alternative rejected:** splitting the context update into six parallel
AI calls (one per domain) was considered. This would eliminate cross-
context interference entirely but at the cost of losing *cross-context
awareness*. A single model call can recognize that a goblin dying affects
combat context (participant removed), social context (NPCs react), and
exploration context (the area is now safe to search). Six isolated calls
cannot make those connections. The selective approach preserves this
awareness while still reducing scope.

### 19. Travel tracking through the pipeline

**Decision:** the pipeline explicitly tracks travel and distance changes
across three steps:

1. **MechanicalEvaluation** (traversal domain only): the prompt instructs
   the model to estimate travel time and distance using Pathfinder 1e
   overland movement rules (speed, mount, terrain, forced march). The
   estimate appears in the `mechanical_summary`.
2. **Ruling**: a `mutations.travel` object
   (`{ hours_traveled, distance_covered, new_location }`) captures the
   mechanical travel outcome alongside HP/condition mutations.
3. **Context Update**: the prompt explicitly instructs the model to update
   `traversal_context.current_location` from `travel.new_location` and to
   enforce narrative consistency (never carry forward a stale location that
   contradicts the factual outcome).

**Why:** without this chain, travel was a "gap" in the pipeline. The
evaluation step asked for Constitution checks (forced march fatigue) but
never computed how far the player traveled. The ruling step processed the
roll but left `position: null`. The Narrate step might creatively advance
the player, but the Context Update step would see no mechanical signal and
carry forward the old location unchanged. This created a state where the
narrative says the player arrived at the village but the context still says
"2 days away."

**Trade-off accepted:** the travel estimate is approximate — the model
computes an estimate based on rules of thumb (light horse ~48 mi/day on
road), not a precise simulation. This is acceptable because the DM
narrative is inherently approximate about distances, and the key
requirement is that *relative position updates* (closer, arrived, departed)
are mechanically tracked rather than left to creative interpretation.

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

### 21. Domain-specific instruction partials

**Decision:** both the MechanicalEvaluation step and the
InterpretationDispatcher load domain-specific instructions from separate
partial files (`templates/mechanical_evaluation/_combat.text.erb`,
`templates/dispatcher/_traversal.text.erb`, etc.) rather than inlining
all domain logic in a single template with `if/elsif` blocks.

**How:** `PromptRenderer.render_partial("mechanical_evaluation/_#{domain}")`
loads the partial for the current domain. If no partial exists, it returns
an empty string gracefully. The rendered text is injected into the main
template via `@domain_instructions`.

**Why:** with six domains each needing domain-specific Pathfinder 1e
guidance (combat: AoO, flanking, concentration; traversal: overland
movement, forced march; social: diplomacy DCs; etc.), a single template
with conditionals became unwieldy. Separate files are easier to review,
edit, and version-control independently.

**Domains covered:** `combat`, `traversal`, `social`, `exploration`,
`rest`, `inventory`.

### 22. Scene summary as player-facing status

**Decision:** the Micro Context Update step produces a `scene_summary`
— a single concise sentence (under 15 words) describing the player's
current situation. It is persisted on the `Adventure` model and displayed
in the player-facing UI.

**Why:** the raw micro-context JSONB fields are developer/admin-oriented
data (key-value pairs like `current_location`, `active: true`, etc.) that
are not meaningful to the player. The scene summary bridges this gap by
giving the player a quick status line ("Traveling by horseback toward the
village.") without exposing internal state tracking.

**UI behavior:** all players see the scene summary. Admin users
additionally see a collapsible "Micro Contexts" debug section showing all
six raw context objects.

### 23. Player-visible roll explanations

**Decision:** when the pipeline pauses for player rolls, the roll request
message now contains the evaluation summaries as human-readable content
rather than the static placeholder "The DM awaits your rolls..."

**How:** `DungeonMasterService#roll_explanation` strips `[DOMAIN]`
prefixes from the mechanical evaluation summaries and joins them into a
paragraph. The summaries explain the mechanical reasoning behind the
requested rolls.

**Why:** players were confused by roll requests that appeared without
context (e.g., two identical-looking Constitution checks without
explanation). The evaluation summaries already contain the "why" — they
just weren't being shown.

### 24. Sanitize/Classify split (parallel gate)

**Decision:** split the original Triage step into two parallel steps:
Sanitize (security filter) and Classify (domain categorization).

**Why:** combining security scoring and action classification in a single
prompt caused both tasks to degrade. When the model was thinking about
danger scores, it sometimes misclassified actions. When it was classifying,
it sometimes under-scored genuinely dangerous inputs. The tasks are
independent — security analysis doesn't need domain knowledge, and domain
classification doesn't need security awareness.

By running them in parallel, neither task is degraded, and total latency
is unchanged (wall-clock time equals the slower of the two calls).

Sanitize can kill the pipeline if `danger_score >= sanitization_threshold`
(configurable in DmConfig). This gate fires before any expensive
downstream calls.

### 25. InterpretationDispatcher (parallel per-domain interpretation)

**Decision:** after the Intent step produces a pure intention, dispatch
parallel per-domain interpreters that each evaluate how the action affects
their domain.

**Why:** asking a single Intent step to handle pure intention extraction
AND domain-specific rule interpretation AND context routing overloaded
the prompt. The Intent step frequently misidentified affected contexts
when it was also trying to determine mechanics. By separating "what does
the player want?" (Intent) from "how does that affect combat/traversal/
social?" (dispatchers), each task gets focused attention.

The dispatcher model is configurable via `interpreter_scope`:
- `"all"` (default): every domain gets a dispatcher call, erring on the
  side of caution
- `"filtered"`: only the classified domain + active contexts get calls,
  reducing cost at the risk of missing cross-domain effects

### 26. CapabilityGuardrail (character validation)

**Decision:** add a dedicated step that validates whether the player
actually possesses the spells, feats, or items they're attempting to use.
Runs in parallel with MechanicalEvaluation.

**Why:** the original pipeline had no explicit capability check. The
mechanical evaluation step was supposed to reject impossible actions,
but a model focused on "what rolls are needed?" frequently assumed the
player could cast a spell they didn't know or use an item they didn't
have. Splitting validation into its own step ensures it's never overlooked.

Two modes are available via `guardrail_mode`:
- `"code"` (default): deterministic fuzzy-match against the character
  sheet. Fast, no AI cost, but limited to exact name matching.
- `"ai"`: an AI call that holistically validates the action against the
  full character block. More nuanced but costs an API call.

Both modes fail open on errors (return `allowed: true`) to avoid blocking
the player on a validation failure.

### 27. Evaluate as code-only synthesis step

**Decision:** make the Evaluate step a pure code step with no AI call.
It sits between Ruling and the output phase (Narrate + ContextUpdate),
packaging results and dispatching the output steps.

**Why:** the original Evaluate step was an AI call that duplicated work
already done by the Ruling step. Both received roll results and produced
outcomes — the only difference was that Evaluate was supposed to be
"factual" and Ruling was "mechanical." In practice, the model often
contradicted itself between the two. By making Evaluate a code-only
routing layer, we eliminate the redundancy and guarantee consistency.

### 28. Narration mode toggle (parallel vs. subjugated)

**Decision:** the output phase supports two modes via `narration_mode`:
- `"parallel"` (default): Narrate and ContextUpdate run concurrently
- `"subjugated"`: ContextUpdate runs first, then Narrate runs with
  fresh DB state

**Why:** in parallel mode, Narrate and ContextUpdate don't see each
other's output. This is usually fine — Narrate works from the ruling
outcome, and ContextUpdate works from the factual "what happened" seed.
However, in subjugated mode, Narrate can read the freshly updated
contexts, which may produce more consistent results at the cost of
higher latency (sequential instead of parallel).

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

---

## Architecture Overview

Every player message flows through `DungeonMasterService`, a thin
orchestrator that handles message persistence and error handling. The
actual pipeline logic lives in `DungeonMaster::Pipeline`, which runs
steps sequentially and returns a result hash. The service maps that
result to persisted `AdventureMessage` records.

When `async_pipeline` is enabled in DmConfig, the controller persists the
player message, enqueues a `PipelineJob` on Sidekiq, and returns 202
immediately. The job runs the pipeline and broadcasts results via
ActionCable. See `docs/async_pipeline_design.md` for details.

```
Player input
    │
    ▼
┌──────────────────────────────┐
│   DungeonMasterService       │  Persists messages, catches errors
│   (thin orchestrator)        │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│   DungeonMaster::Pipeline    │  Pure pipeline logic (budget mode)
│   — OR —                     │
│   DungeonMaster::EdgePipeline│  Single-call alternative (edge mode)
│                              │
│   run_prompt(input)          │
│   run_rolls(results, meta)   │
└──────────────────────────────┘
```

The pipeline has **two entry points**:

1. `run_prompt(player_input)` — player typed something new
2. `run_rolls(roll_results, metadata)` — player submitted dice results

---

## Flow Diagram

```
run_prompt(player_input)
    │
    ▼
┌────────────────────────────┐
│   GATE (parallel)          │
│   ┌──────────┐ ┌────────┐ │
│   │ SANITIZE │ │CLASSIFY│ │    danger >= threshold
│   └────┬─────┘ └───┬────┘ │───────────────────────► { action: :rejected }
└────────┼───────────┼───────┘
         │           │
         │  category == "dm_query"
         ├───────────┼──────────────► CHRONICLER ──► DM QUERY ──► { action: :dm_query }
         │           │
         ▼           ▼
┌─────────────────────────────┐
│ INTENT (pure restatement)   │
└──────────────┬──────────────┘
               │
               ▼
┌────────────────────────────────────┐
│ INTERPRETATION DISPATCHERS         │
│ (parallel: one per domain)         │
│ ┌─────┐┌─────┐┌─────┐┌─────┐ ... │
│ │cbt  ││trav ││soc  ││expl │      │
│ └──┬──┘└──┬──┘└──┬──┘└──┬──┘      │
│    └───┬──┴──┬──┘───┬──┘          │
│        ▼ CONVERGE (code)          │
└──────────────┬─────────────────────┘
               │
               │  needs_mechanics == false
               ├──────────────────────────────► EVALUATE (code) ──► OUTPUT PHASE
               │
               │  needs_mechanics == true
               ▼
┌──────────────────────────────────┐
│  MECHANICS GATE (parallel)       │
│  ┌──────────────┐ ┌───────────┐ │
│  │ MECH. EVAL   │ │CAPABILITY │ │
│  │ (loop per    │ │GUARDRAIL  │ │
│  │  context)    │ │           │ │
│  └──────┬───────┘ └─────┬─────┘ │
└─────────┼───────────────┼────────┘
          │               │
          │    guardrail rejected?
          │    ├── yes ──► { action: :rejected }
          │    │
          ▼    ▼
     player rolls needed?
          │
          ├── yes ──► { action: :awaiting_rolls }
          │                 │
          │                 ▼ (player submits rolls later)
          │           run_rolls(results, metadata)
          │                 │
          │                 ▼
          │           ┌─────────────────┐
          │           │ RESTORE STATE   │  (from metadata)
          │           └────────┬────────┘
          │                    │
          ├── no ──────────────┤
          │                    │
          ▼                    ▼
┌──────────────────────────────────────────┐
│            RESOLUTION FLOW               │
│  1. Resolve NPC actions (app-side rolls) │
│  2. RULING (AI — post-roll arbitration)  │
│  3. Apply mutations (app-side)           │
│  4. CHRONICLER (plot state, optional)    │
│  5. EVALUATE (code — synthesis/routing)  │
│  6. OUTPUT PHASE                         │
│     ┌───────────────────────────────┐    │
│     │ narration_mode == "parallel": │    │
│     │   NARRATE    ║  CONTEXT UPD.  │    │
│     │   (parallel) ║  6a. Micro     │    │
│     │              ║  6b. Macro     │    │
│     ├───────────────────────────────┤    │
│     │ narration_mode == "subjugated"│    │
│     │   CONTEXT UPD. → then NARRATE │    │
│     └───────────────────────────────┘    │
└──────────────────────────────────────────┘
                    │
                    ▼
          { action: :narrated }
```

---

## Step 1a: Sanitize

**File:** `app/services/dungeon_master/steps/triage.rb` (`run_sanitize`)
**Template:** `app/services/dungeon_master/templates/sanitize.text.erb`
**Pipeline step name:** `sanitize`

### Purpose

Security filter. Scores the player input for danger on a 0-100 scale.
Runs in parallel with Classify (no dependencies between them).

Danger categories: prompt injection, meta-gaming, rule manipulation,
DM behavior directives, out-of-character harassment.

### Input

| Field | Source |
|---|---|
| System prompt | `sanitize.text.erb` (static, no dynamic bindings) |
| User message | Raw player input (unmodified) |

### Output (JSON)

```json
{
  "danger_score": 0,
  "sanitized_input": "cleaned version of the player's input",
  "reason": "explanation of danger assessment, null if safe"
}
```

### App-side post-processing

- If `danger_score >= sanitization_threshold`: pipeline returns
  `{ action: :rejected }` immediately. No further AI calls are made.
- The `sanitized_input` (not the raw input) is forwarded to all
  subsequent steps.

### Design rationale

Sanitize is intentionally the cheapest, simplest step with a static
prompt (no dynamic context). It's a pure gatekeeper: fast to execute,
cheap to run, and its failure mode (rejecting safe input) is far less
damaging than letting malicious input through.

---

## Step 1b: Classify

**File:** `app/services/dungeon_master/steps/triage.rb` (`run_classify`)
**Template:** `app/services/dungeon_master/templates/classify.text.erb`
**Pipeline step name:** `classify`

### Purpose

Action classifier. Categorizes the player input into exactly one game
domain. Runs in parallel with Sanitize.

### Input

| Field | Source |
|---|---|
| System prompt | `classify.text.erb` (static, no dynamic bindings) |
| User message | Raw player input (unmodified) |

### Output (JSON)

```json
{
  "category": "traversal",
  "classification_reasoning": "why this category was chosen"
}
```

Valid categories: `combat`, `traversal`, `social`, `exploration`, `rest`,
`inventory`, `dm_query`.

### App-side post-processing

- The `category` is normalized and validated against the allowed list;
  unrecognized categories raise `AiError`.
- If `category == "dm_query"`, the pipeline branches to the DM Query fast
  path.
- Otherwise, the category is passed to the InterpretationDispatcher to
  influence domain selection (when `interpreter_scope` is `"filtered"`).

### Design rationale

Classification is based on **purpose**, not surface mechanics. "I cast
Mount and ride to the village" is `traversal`, not `combat`. The template
includes explicit rules for this to prevent misclassification of utility
spells and in-character dialogue.

---

## Step 1c: DM Query (fast path)

**File:** `app/services/dungeon_master/steps/dm_query.rb`
**Template:** `app/services/dungeon_master/templates/dm_query.text.erb`
**Pipeline step name:** `dm_query`

### Purpose

Answers out-of-character player questions ("What are my known spells?",
"How does grappling work?", "What can I see around me?") without
advancing the scene or triggering any mechanics.

This is a **fast path**: when Classify categorizes the input as `dm_query`,
the pipeline skips Intent, dispatchers, evaluation, ruling, narration, and
context updates entirely. The question goes in, an answer comes out,
nothing changes.

### Input

| Field | Source |
|---|---|
| System prompt | `dm_query.text.erb` bound with: story title, story summary, formatted micro-contexts, DM guidance text, spoiler guidance from Chronicler (if available) |
| User message | Sanitized player input (from Sanitize) |

### Output (JSON)

```json
{
  "answer": "The DM's answer to the player's question",
  "reasoning": "What informed the answer"
}
```

### App-side post-processing

- The `answer` is persisted as a `dm_query` message type (role: `dm`).
- No context is updated. No mutations are applied. No state changes.

### Design rationale

Many player messages are questions, not actions. Routing them through the
full pipeline would be wasteful and could cause unintended side effects
(context updates reflecting a non-event). The fast path keeps query
latency low and cost minimal.

---

## Step 2: Intent

**File:** `app/services/dungeon_master/steps/intent.rb`
**Template:** `app/services/dungeon_master/templates/intent.text.erb`
**Pipeline step name:** `intent`

### Purpose

Pure intent interpretation. Restates what the player is trying to do in
clear, unambiguous language. Does NOT evaluate rules, determine required
rolls, classify domains, or identify affected contexts — those
responsibilities belong to the InterpretationDispatcher.

### Input

| Field | Source |
|---|---|
| System prompt | `intent.text.erb` (static, no dynamic bindings) |
| User message | Sanitized player input (from Sanitize) |

### Output

A string: the clear restatement of the player's intention. The Intent
step returns `parsed["intention"]` directly (not a hash).

```json
{
  "intention": "Clear, unambiguous restatement of what the player wants to do",
  "reasoning": "Brief explanation of how you interpreted the input"
}
```

### Design rationale

Intent is deliberately minimal. By separating "what does the player want?"
from "how does that affect the game?", the Intent step produces a clean,
unambiguous seed that domain-specific dispatchers can evaluate
independently. Keeping the prompt static (no context injection) makes it
fast and cheap.

---

## Step 3: InterpretationDispatcher

**File:** `app/services/dungeon_master/steps/interpretation_dispatcher.rb`
**Template:** `app/services/dungeon_master/templates/interpretation_dispatcher.text.erb`
**Pipeline step name:** `dispatcher`

### Purpose

Parallel per-domain interpretation. Given the pure intention from the
Intent step, each dispatcher evaluates how the action affects its domain
(combat, traversal, social, exploration, rest, inventory). Results are
merged by a code-based convergence step.

### Domain selection

Controlled by `DmConfig` `interpreter_scope`:
- `"all"` (default): all six domains are dispatched
- `"filtered"`: only the Classify category + active contexts are dispatched

### Input (per domain)

| Field | Source |
|---|---|
| System prompt | `interpretation_dispatcher.text.erb` bound with: domain name, domain-specific character data, domain micro-context, domain rules manifest, domain-specific instruction partial, extra context (story locations for traversal) |
| User message | The intention string (from Intent step) |

### Output (JSON, per domain)

```json
{
  "affected": false,
  "needs_mechanics": false,
  "macro_significant": false,
  "rules_needed": [],
  "domain_interpretation": "How this action relates to this domain",
  "transition": null,
  "time_spanning": false,
  "time_span_type": null,
  "destination": null,
  "estimated_hours": null,
  "reasoning": "Brief explanation"
}
```

### Convergence (code-only)

`converge_dispatchers` merges all domain results into a unified intent
hash:
- `affected_contexts`: domains where `affected == true`
- `needs_mechanics`: any affected domain needs mechanics
- `macro_significant`: any domain flagged it
- `rules_needed`: union of all affected domains' rules
- `primary_context`: the Classify category if it's affected, otherwise
  the first affected domain
- `time_spanning`: true if traversal or rest dispatcher flagged it
- `plot_relevant`: determined by `determine_plot_relevance` (checks for
  undiscovered clues and story NPCs)

### Error handling

Individual dispatcher failures are non-fatal. A failed dispatcher returns
`affected: false`, ensuring the pipeline can continue with the remaining
domains. The error is logged.

### Design rationale

The dispatcher pattern gives each domain focused attention. A combat
dispatcher can reason about AoO triggers without being distracted by
traversal movement rules. Running them in parallel means wall-clock time
equals the slowest single domain, not the sum of all domains.

---

## Step 4a: MechanicalEvaluation

**File:** `app/services/dungeon_master/steps/mechanical_evaluation.rb`
**Template:** `app/services/dungeon_master/templates/mechanical_evaluation.text.erb`
**Pipeline step name:** `mechanical_evaluation`

### Purpose

The rules engine. Determines what dice rolls are needed, what NPC actions
occur, and what automatic consequences follow — all within Pathfinder 1e
rules. Runs in parallel with CapabilityGuardrail.

Each domain receives **domain-specific instructions** loaded from partial
files (`templates/mechanical_evaluation/_combat.text.erb`,
`_traversal.text.erb`, etc.). These partials contain Pathfinder 1e rules
guidance relevant to that domain.

### The loop

This step runs **once per affected context** identified by the dispatchers.
The primary context is processed first, so subsequent evaluations can
reference its summary.

```
Iteration 1: MechanicalEvaluation for COMBAT
  → "Player attacks Goblin A, provoking AoO from Goblin B"
  → mechanical_summary: "[COMBAT] Player swings at Goblin A..."

Iteration 2: MechanicalEvaluation for TRAVERSAL
  → receives previous summary: "[COMBAT] Player swings at Goblin A..."
  → "Player also attempts to move 10 feet toward the door"
  → mechanical_summary: "[TRAVERSAL] Player moves toward the door..."
```

### Input (per iteration)

| Field | Source |
|---|---|
| System prompt | `mechanical_evaluation.text.erb` bound with: domain name, domain-specific character block, micro-context for this domain, creature/NPC stat blocks, previous evaluation summaries, fetched rules text, domain-specific instruction partial |
| User message | The player's intention (from Intent step) |

### Output (JSON, per iteration)

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

### App-side post-processing

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

### Design rationale

The evaluation step is deliberately scoped to one domain per call. The
`player_rolls` / `npc_actions` split is also deliberate: player rolls are
resolved by the player (submitted via UI), while NPC rolls are resolved
deterministically by the app.

---

## Step 4b: CapabilityGuardrail

**File:** `app/services/dungeon_master/steps/capability_guardrail.rb`
**Template:** `app/services/dungeon_master/templates/capability_guardrail.text.erb` (AI mode only)
**Pipeline step name:** `capability_guardrail`

### Purpose

Validates that the player actually possesses the spells, feats, or items
they are attempting to use. Runs in parallel with MechanicalEvaluation.

### Modes

Controlled by `DmConfig` `guardrail_mode`:

**Code mode** (`"code"`, default): deterministic fuzzy-match against the
character sheet. Regex patterns extract spell/feat/item references from
the intention text and check them against the sheet's known names.
No AI call — zero cost, sub-millisecond execution.

**AI mode** (`"ai"`): sends the full character block and intention to an
AI model for holistic validation. More nuanced (can catch implicit
references, prerequisite chains) but costs an API call.

### Output

```json
{
  "allowed": true,
  "reason": null
}
```

When `allowed` is `false`, the pipeline returns `{ action: :rejected }`
with the guardrail's `reason`.

### Error handling

Both modes fail open on errors — they return `{ allowed: true }`. This
prevents a validation system error from blocking the player. Errors are
logged for admin review.

### Design rationale

Capability validation was previously embedded in the mechanical evaluation
prompt, which frequently overlooked it. A dedicated guardrail ensures
validation never competes with other concerns for the model's attention.
Running it in parallel with MechanicalEvaluation means zero additional
latency.

---

## App-side: NPC Roll Resolution

**File:** `app/services/dungeon_master/mutations.rb` (`resolve_npc_actions`)

### Purpose

Rolls dice for NPC actions deterministically. This is **not** an AI step —
it's pure application logic using `rand(1..20)`.

### Input

The merged `npc_actions` array from the MechanicalEvaluation step.

### Logic

For each NPC action:
1. Roll d20
2. Add the NPC's modifier (from the evaluation)
3. Compare against the player's AC (from the character sheet)
4. Produce a textual result: `"Goblin A attack -> rolled 14 + 3 = 17 vs AC 15: HIT"`

### Output

A text block of all NPC roll results, which feeds into the Ruling step.

### Design rationale

Having the app roll for NPCs ensures consistency and prevents the AI from
fudging results. The rolls use the modifiers specified by the mechanical
evaluation (which referenced actual creature stat blocks), keeping the
resolution grounded in real numbers.

---

## App-side: Player Roll Submission

When the pipeline returns `{ action: :awaiting_rolls }`, the UI presents
the player with the required rolls. The player submits their results,
which re-enter the pipeline through `DungeonMasterService#process_roll_result`.

This calls `Pipeline#run_rolls`, which:
1. Restores the intent and merged evaluation data from the persisted
   `roll_request` message metadata
2. Feeds everything into the Resolution Flow

---

## Step 5: Ruling

**File:** `app/services/dungeon_master/steps/ruling.rb`
**Template:** `app/services/dungeon_master/templates/ruling.text.erb`
**Pipeline step name:** `ruling`

### Purpose

Post-roll arbitration. Takes the dice results (both player and NPC), the
mechanical evaluation summaries, and the character sheet, and determines
the factual mechanical outcome. Did the attack hit? How much damage? Did
the save succeed? What conditions apply?

The output is factual, not narrative. It produces structured **mutations**
that the app applies to the database.

### Input

| Field | Source |
|---|---|
| System prompt | `ruling.text.erb` bound with: full player character block, mechanical evaluation summaries text, combined roll results (player + NPC), pending consequences, formatted micro-contexts |
| User message | The player's intention (from Intent step) |

### Output (JSON)

```json
{
  "outcome": "Factual summary of what happened mechanically",
  "reasoning": "How rolls were evaluated",
  "mutations": {
    "player": {
      "hp_change": -5,
      "conditions_add": ["prone"],
      "conditions_remove": [],
      "position": "in the sacred lake"
    },
    "npcs": [
      {
        "name": "Goblin A",
        "hp_change": -8,
        "conditions_add": [],
        "conditions_remove": [],
        "defeated": false,
        "attitude_change": null
      }
    ],
    "items_consumed": ["Potion of Cure Light Wounds"],
    "spells_used": ["Magic Missile"],
    "travel": {
      "hours_traveled": 10,
      "distance_covered": "~40 miles on horseback along road",
      "new_location": "approaching the village outskirts"
    }
  }
}
```

The `travel` field is present when the action involves movement or travel.
It is `null` when no meaningful movement occurs.

### App-side post-processing

The `mutations` hash is applied by `DungeonMaster::Mutations#apply_mutations`:
- **Player HP**: clamped between `-constitution` (death threshold) and
  `max_hp`
- **NPC HP**: clamped between 0 and `max_hp`
- **NPC attitude changes**: validated against `CreatureSheet::ATTITUDES`
  before persisting
- **Travel**: flows through to the Context Update step where it drives
  `traversal_context.current_location` updates
- **Conditions, items, spells**: logged but not yet mechanically enforced
  (future enhancement)

The `outcome` text is forwarded as the `narrate_seed` to the Evaluate
(synthesis) step.

### Design rationale

Separating ruling from narration ensures the mechanical outcome is
determined objectively before the narrative is written. The mutations
structure is intentionally explicit (HP changes, not "takes damage") so
the app can apply them without interpreting natural language.

---

## Step 5b: Chronicler

**File:** `app/services/dungeon_master/steps/chronicler.rb`
**Template:** `app/services/dungeon_master/templates/chronicler.text.erb`
**Pipeline step name:** `chronicler`

### Purpose

Plot state management and spoiler gating. Evaluates whether the player's
action reveals story clues, triggers NPC reactions, or reaches milestones.
Produces a "DM Brief" that guides the Narrate step on what to describe,
hint at, or avoid.

Runs conditionally when the adventure has structured story data
(StoryNpc, StoryClue records). A deterministic heuristic fallback
(`heuristic_chronicler`) handles clue discovery when the AI Chronicler is
skipped.

### Input

| Field | Source |
|---|---|
| System prompt | `chronicler.text.erb` bound with: enriched premise, current plot state (discovered/attempted clues, met NPCs, milestones), player's action and outcome, undiscovered clues with discovery conditions, available NPCs at current location |
| User message | "Evaluate plot state for this action." |

### Output (JSON)

```json
{
  "clues_to_reveal": [{ "id": 1, "title": "..." }],
  "clues_attempted": [{ "id": 2, "title": "...", "reason": "why it failed" }],
  "npc_reactions": { "NPC Name": "brief reaction instruction" },
  "atmosphere_notes": "optional atmospheric detail",
  "milestones_reached": [{ "title": "...", "consequence": "..." }],
  "narration_guidance": "DM Brief for the narrator",
  "plot_state_updates": {
    "discovered_clues_add": [1],
    "attempted_clues_add": [2],
    "npc_met_add": [3],
    "custom_facts_add": ["free-text fact"]
  },
  "reasoning": "Evaluation logic"
}
```

### App-side post-processing

- `plot_state_updates` are merged into the adventure's `plot_state` JSONB
- The `narration_guidance` string becomes the `dm_brief` parameter passed
  to the Narrate step

### Design rationale

The Chronicler separates plot awareness from narration. The narrator
never sees the full premise or unrevealed secrets — it only receives the
`dm_brief`, which tells it what to describe without spoiling what it
shouldn't know. This prevents the narration model from accidentally
leaking future plot points.

---

## Step 6: Evaluate (code-only synthesis)

**File:** `app/services/dungeon_master/steps/evaluate.rb`
**Pipeline step name:** (no AI call — no step name in logs)

### Purpose

Code-only synthesis and routing step. Sits between the Ruling step and
the output phase (Narrate + ContextUpdate). No AI call.

Responsibilities:
1. Package the ruling outcome and DM brief into a `narrate_seed`
2. Package the factual outcome and mutations into directives for
   ContextUpdate
3. Dispatch the output phase based on `narration_mode` config

### narration_mode

- `"parallel"` (default): Narrate and ContextUpdate run concurrently in
  threads. Lower latency, but Narrate doesn't see fresh context.
- `"subjugated"`: ContextUpdate runs first, then Narrate. Higher latency,
  but Narrate can read the freshly updated contexts.

### Design rationale

This step exists as a routing layer to keep the pipeline's flow method
clean. By encapsulating the parallel-vs-sequential decision and the
data packaging in one place, the main flow methods (`run_action_flow`,
`run_resolution_flow`) remain simple dispatchers.

---

## Step 7: Narrate

**File:** `app/services/dungeon_master/steps/narrate.rb`
**Template:** `app/services/dungeon_master/templates/narrate.text.erb`
**Pipeline step name:** `narrate`

### Purpose

The player-facing creative step. Takes the mechanical outcome (or nothing,
for non-mechanical actions) and produces the DM's narrative response.
This is the text the player actually reads.

### Input

| Field | Source |
|---|---|
| System prompt | `narrate.text.erb` bound with: story title, story context (hook + atmosphere + DM brief), story summary, formatted micro-contexts, mechanical outcome text (from Ruling, or nil), player action and intent (for non-mechanical path), pacing instructions, directed play instructions |
| User message | The outcome text (mechanical path), or the player's action text (non-mechanical path) |

### Output (JSON)

```json
{
  "narrative": "The DM's vivid narrative prose",
  "adventure_complete": false
}
```

### Key fields explained

- **`narrative`**: the text shown to the player. Written in DM voice,
  respecting pacing settings.
- **`adventure_complete`**: when `true`, the service persists an
  additional `adventure_complete` system message. This signals the UI
  that the adventure has concluded.

### Pacing control

The narrate template receives `pacing_text` which varies based on
DmConfig settings:
- **Verbose off**: instructs the DM to keep responses to 1-2 paragraphs
  within the configured word range (default: min 80, max 150 words)
- **Verbose on**: no word limits, the DM may write longer, richer
  responses

### Directed play

When the adventure has `directed_dm` enabled, the template includes
additional instructions that guide the DM to steer the narrative
toward the story's premise and hooks, ensuring the adventure progresses
even with a passive player.

### Design rationale

Narration is deliberately isolated from mechanical resolution. The model
receives a factual outcome ("you hit for 8 damage, goblin has 4 HP
remaining") and transforms it into prose. It does not adjudicate rules,
determine hit/miss, or decide outcomes — that was done in Ruling.

---

## Step 8a: Micro Context Update

**File:** `app/services/dungeon_master/steps/context_update.rb`
**Template:** `app/services/dungeon_master/templates/micro_context_update.text.erb`
**Pipeline step name:** `micro_context_update`

### Purpose

Updates the micro-context JSONB fields on the Adventure model
(`traversal_context`, `combat_context`, `social_context`,
`exploration_context`, `rest_context`, `inventory_context`) to reflect
what just happened.

Only **relevant** contexts are included in the prompt: those flagged as
`affected_contexts` by the dispatchers plus any that already contain
data (active contexts). This reduces output size and keeps the model
focused on what actually changed.

Receives the factual outcome summary (`what_happened`) and mutations —
NOT the narrative text. This decouples context accuracy from narrative
style.

### Input

| Field | Source |
|---|---|
| System prompt | `micro_context_update.text.erb` bound with: the factual outcome (`what_happened`), mutations JSON, context sections (only relevant contexts, labelled `[UPDATE]` or `[maintain]`), list of relevant and affected field names |
| User message | "Update contexts based on the above." |

### Output (JSON)

Only the relevant contexts appear in the output:

```json
{
  "traversal_context": {
    "current_location": "Sacred Lake shore",
    "terrain": "shallow water",
    "nearby_npcs": ["Village Elder"],
    "exits": ["north path", "lake center"]
  },
  "combat_context": {
    "active": true,
    "round": 3,
    "participants": [
      { "name": "Goblin A", "hp": 4, "conditions": [], "position": "10ft north" }
    ]
  },
  "social_context": {
    "npcs_present": [
      { "name": "Village Elder", "attitude": "unfriendly", "notes": "angry about sacred lake" }
    ]
  },
  "new_creatures": ["Water Elemental"],
  "scene_summary": "Fighting goblins at the Sacred Lake shore.",
  "reasoning": "Combat continues, traversal updated to lake, social tension with Elder"
}
```

### Scene summary

The context update step also produces a `scene_summary` — a single
concise sentence (under 15 words) describing the player's current
situation. Persisted on the `Adventure` model and shown in the UI.

### Context field schemas

**Traversal:** `current_location`, `destination`, `terrain`, `weather`,
`time_of_day`, `nearby_npcs`, `points_of_interest`, `exits`

**Combat:** `active`, `round`, `current_turn`, `turn_order`,
`participants` (name, hp, conditions, position), `terrain_notes`,
`active_effects`

**Social:** `scene`, `npcs_present` (name, role, attitude, notes),
`conversation_state`, `stakes`, `persuasion_progress`

**Exploration:** `searched_areas`, `discovered_items`, `discovered_secrets`,
`knowledge_checks_attempted`, `active_detection`, `pending_investigations`

**Rest:** `resting`, `hours_completed`, `total_hours_needed`, `watch_order`,
`interruptions`, `spells_prepared`, `hp_recovered`, `rest_complete`

**Inventory:** `recently_acquired`, `recently_used`,
`pending_identifications`, `equipped_changes`,
`notable_consumables_remaining`

### App-side post-processing

- Each non-empty context updates the corresponding Adventure JSONB field
- `scene_summary` updates the Adventure `scene_summary` column
- If `new_creatures` is present, the app performs a **bestiary lookup**
  for each name via `handle_new_creatures`. Matching `BestiaryEntry`
  records produce `CreatureSheet` instances with deterministically rolled
  HP.

---

## Step 8b: Macro Narrative Update

**File:** `app/services/dungeon_master/steps/context_update.rb`
**Template:** `app/services/dungeon_master/templates/macro_narrative_update.text.erb`
**Pipeline step name:** `macro_narrative_update`

### Purpose

Updates the adventure's `story_summary` field — the high-level "story so
far" that carries across the entire adventure. Only runs when the
dispatchers flagged the action as `macro_significant`.

### Input

| Field | Source |
|---|---|
| System prompt | `macro_narrative_update.text.erb` bound with: story hook/title, current story summary, factual outcome (`what_happened`) |
| User message | "Update the story summary." |

### Output (JSON)

```json
{
  "story_summary": "Updated story-so-far summary (3-8 sentences)",
  "reasoning": "What was added/changed"
}
```

### Execution

Steps 8a and 8b run **in parallel** (Ruby threads). The macro update is
conditional — it only fires when `macro_significant` is true. If both
run, they execute concurrently since they write to different fields.

### Design rationale

The story summary feeds into every future Narrate prompt, giving the DM
long-term memory. But updating it on every turn would cause bloat and
inaccuracy. The `macro_significant` flag from the dispatchers acts as a
filter: only story-changing events (quest completion, boss defeat, plot
revelation) trigger an update.

---

## Edge Pipeline (alternative mode)

**File:** `app/services/dungeon_master/edge_pipeline.rb`
**Template:** `app/services/dungeon_master/templates/edge_pipeline.text.erb`
**Pipeline step name:** `edge_pipeline`

### Purpose

A monolithic single-call alternative to the budget pipeline. Handles
sanitization, intent, capability checks, mechanics (with internally
simulated dice rolls), mutations, narration, and context updates all
in one response.

Activated when `DmConfig` `pipeline_mode` is set to `"edge"`.

### Trade-offs vs. budget pipeline

| | Budget Pipeline | Edge Pipeline |
|---|---|---|
| Latency | 5-15s (10+ round-trips) | 2-5s (1 round-trip) |
| Per-step model control | Yes | No |
| Per-step token budgets | Yes | No |
| Roll requests to player | Yes | No (AI simulates internally) |
| Debugging granularity | Per-step logs | Single opaque log |
| Cost tuning | Cheap steps use nano models | One model for everything |

### Input

| Field | Source |
|---|---|
| System prompt | `edge_pipeline.text.erb` bound with: full character block, creature stats, story block, micro-contexts, pacing instructions, directed play instructions, dm_query_mode flag |
| User message | Raw player input |

### Output (JSON)

```json
{
  "rejected": false,
  "rejection_reason": null,
  "narrative": "The DM's response",
  "adventure_complete": false,
  "mutations": { ... },
  "context_updates": { ... },
  "scene_summary": "Current situation",
  "story_summary_update": null,
  "reasoning": "Internal reasoning"
}
```

In DM query mode, replaces `narrative` with `dm_answer`.

### App-side post-processing

- If `rejected`: return `{ action: :rejected }`
- If `dm_answer`: return `{ action: :dm_query }`
- Otherwise: apply mutations, persist context updates, persist scene
  summary, optionally update story summary, return
  `{ action: :narrated }`

### Design rationale

Edge mode exists for scenarios where the budget pipeline's latency or
complexity is unacceptable. It's a deliberate trade-off: less accurate,
less debuggable, less configurable, but faster and simpler. The
`pipeline_mode` toggle lets the admin switch between modes without code
changes.

---

## App-side: Mutation Application

**File:** `app/services/dungeon_master/mutations.rb`

This module handles all non-AI state changes between the Ruling and
Narrate steps.

### `apply_mutations(mutations)`

Applies the structured mutations hash from the Ruling step:

- **Player HP changes**: applied to the player's `CreatureSheet`,
  clamped between negative constitution (death) and max HP
- **NPC HP changes**: applied to matching `CreatureSheet` records,
  clamped between 0 and max HP
- **NPC attitude changes**: validated against the
  `CreatureSheet::ATTITUDES` whitelist before persisting

### `handle_new_creatures(creature_names)`

Called by the Micro Context Update step when `new_creatures` is present:

1. Checks if a `CreatureSheet` already exists for this adventure
2. Looks up the name in the `BestiaryEntry` table (case-insensitive)
3. If found, creates a `CreatureSheet` with deterministically rolled HP
   using the bestiary entry's `hp_formula` (e.g. "2d8+4")
4. If not found, logs a warning (the creature appears in narrative but
   has no stat block)

---

## Error Handling

All AI steps follow the same error handling pattern:

1. **`TokenBudgetExceededError`**: raised by `AiClient` when the API
   returns `finish_reason: length`. This is a hard error for critical
   steps — even truncated non-empty responses are rejected. The error is
   logged with `status: "token_budget_exceeded"` and re-raised (for
   sanitize, classify, intent, mechanical evaluation, ruling, narrate) or
   swallowed with an empty result (for context updates and capability
   guardrail, which are non-critical).

2. **`AiError`**: covers API unreachability, malformed responses, and
   other failures. Same re-raise/swallow pattern as above.

3. **Dispatcher resilience**: individual InterpretationDispatcher failures
   return `{ affected: false }` for that domain, allowing the pipeline to
   continue with the remaining domains.

4. **Context update resilience**: Steps 8a and 8b rescue all errors and
   return empty hashes rather than failing the pipeline. A failed context
   update degrades future prompts but doesn't break the current turn.

5. **CapabilityGuardrail resilience**: both code and AI modes fail open
   (`{ allowed: true }`) on errors, preventing validation system failures
   from blocking the player.

At the service level, all errors are caught and translated into a
generic player-facing message: *"The Dungeon Master is momentarily
distracted..."*. Technical details are logged only.

---

## Logging

Every AI call produces an `AiLog` record containing:

| Field | Description |
|---|---|
| `step` | Pipeline step name (sanitize, classify, intent, dispatcher, mechanical_evaluation, capability_guardrail, ruling, chronicler, narrate, micro_context_update, macro_narrative_update, edge_pipeline) |
| `prompt_summary` | Truncated description of what was asked |
| `raw_response` | The complete API response |
| `parsed_response` | The parsed JSON |
| `parse_status` | Whether parsing succeeded, used fallback, etc. |
| `request_body` | The full request (system prompt + user message) |
| `model_used` | Which model actually processed this call |
| `status` | Success, error, or `token_budget_exceeded` |
| `reasoning` | Extracted from the AI's `reasoning` field (when present) |

This makes every pipeline execution fully auditable. The `model_used`
field is especially important with per-step model selection — it records
exactly which model was used, not just which was configured.

---

## Configuration

All pipeline behavior is configurable through `DmConfig` (admin UI at
`/admin/dm_config`):

| Setting | Default | Affects |
|---|---|---|
| `sanitization_threshold` | `30` | Sanitize: danger score cutoff (0-100) |
| `verbose` | `false` | Narrate: enables unconstrained response length |
| `pacing_words_min` | `80` | Narrate: minimum word count target when verbose is off |
| `pacing_words_max` | `150` | Narrate: maximum word count target when verbose is off |
| `temperature` | `0.8` | All steps: creativity/randomness (non-reasoning models only) |
| `model` | `gpt-4o-mini` | Default model for all steps |
| `step_models[step]` | `{}` | Per-step model override |
| `token_budgets[step]` | (see below) | Per-step max completion tokens |
| `pipeline_mode` | `"budget"` | `"budget"` (multi-step) or `"edge"` (single-call) |
| `interpreter_scope` | `"all"` | `"all"` (every domain) or `"filtered"` (classify + active) |
| `guardrail_mode` | `"code"` | `"code"` (deterministic) or `"ai"` (prompt-based) |
| `narration_mode` | `"parallel"` | `"parallel"` (concurrent) or `"subjugated"` (sequential) |
| `async_pipeline` | `false` | When true, pipeline runs in Sidekiq with ActionCable delivery |

### Default token budgets

| Step | Budget |
|---|---|
| `sanitize` | 300 |
| `classify` | 200 |
| `dm_query` | 300 |
| `intent` | 200 |
| `dispatcher` | 400 |
| `mechanical_evaluation` | 500 |
| `capability_guardrail` | 300 |
| `ruling` | 600 |
| `chronicler` | 500 |
| `narrate` | 800 |
| `micro_context_update` | 800 |
| `macro_narrative_update` | 500 |
| `edge_pipeline` | 2000 |

See `docs/pipeline_model_selection.md` for detailed model recommendations
per step.
