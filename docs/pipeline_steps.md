# Dungeon Master Pipeline — Step Reference

Design document describing the AI Dungeon Master pipeline: what each step
does, what it receives, what it produces, and how the steps connect.

**Flow diagram:** [Pipeline diagram](pipeline_diagram.md) (Mermaid flowcharts).

For the guiding principles behind these decisions, see
[Design Philosophy](design_philosophy.md).

For flow and behavioral detail see [pipeline_diagram.md](pipeline_diagram.md).

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

**Alternative preserved:** the Edge Pipeline (see below) collapses all
steps into one call, gated by `pipeline_mode: "edge"`. This is available
for low-traffic deployments or latency-sensitive scenarios where the
trade-offs are acceptable.

**Middle ground preserved:** the Unified Evaluation mode
(`evaluation_mode: "unified"`) collapses only the evaluation phase
(beacons + mechanical evaluations + roll qualifiers) into a single AI
call while preserving the rest of the pipeline (sanity checks, verdict,
time keeping, narration, context updates as separate steps). This
targets top-end models that can handle cross-domain reasoning in one
pass — delivering better coherence and zero roll duplication — without
sacrificing the debugging granularity of the non-evaluation steps.

| | Standard | Unified Evaluation | Edge Pipeline |
|---|---|---|---|
| Evaluation calls | 8-14 (6 beacons + N mecheval + N rollqualifier) | 1 | 1 (everything) |
| Other steps | Separate | Separate | N/A (all-in-one) |
| Per-domain model selection | Yes | No (one model for eval) | No |
| Cross-domain coherence | Low (each domain isolated) | High (single context) | High |
| Roll deduplication | Prompt-level (warn-only, see DD 31) | AI avoids duplicates natively | N/A |
| Prompt size | Small per call | Large (all contexts + rules) | Largest |
| Target models | Any (cheap models work well) | Top-end only (o3, gpt-5, claude-4) | Capable |
| Toggle | default | `evaluation_mode: "unified"` | `pipeline_mode: "edge"` |

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

**Trade-off accepted:** the Mechanic step receives NPC results as text
("Goblin A rolled 14 + 3 = 17 vs AC 15: HIT") rather than structured
data. This is slightly more work to parse but keeps the mechanic prompt
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
considered but would have duplicated verdict, narration, and context
updates — far more expensive and harder to merge into a coherent
narrative.

### 5. Mechanic/Momentum before narration (facts-first ordering)

**Decision:** determine the factual outcome before writing any narrative,
on both the mechanical path (Mechanic) and the non-mechanical path
(Momentum).

**Why:** if the model narrates and evaluates simultaneously, narrative
bias corrupts accuracy. The model might write a dramatic "the goblin
collapses!" moment and then produce mutations showing the goblin at 3 HP
— or vice versa, produce correct mutations but a narrative that
contradicts them.

By running Mechanic (post-roll arbitration) or Momentum (non-mechanical
outcome determination) first, the Narrate step receives a factual outcome
it must faithfully narrate. Both steps write `verdict_outcome` to the
adventure loop, giving Narrate a single read location regardless of path.

**Trade-off accepted:** two AI calls where one might suffice. The cost
is justified by correctness — mechanical errors in a Pathfinder game
(wrong HP, missed saves, ignored conditions) directly degrade the
player's trust in the DM.

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

**Decision:** rules are stored as YAML files keyed by slug. The
Beacon step requests rules by slug, and the app
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

**Trade-off accepted:** the beacon step must correctly identify which
rules are relevant. If it misses a rule, the MechanicalEvaluation step
won't have it. This is mitigated by providing domain-scoped rule
manifests — each beacon sees rules relevant to its domain.

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

### 11. Pipeline class separated from the service

**Decision:** `DungeonMaster::Pipeline` encapsulates pure pipeline logic
(step sequencing, branching, data flow). `DungeonMasterService` handles
only message persistence and error handling.

**Why:** the original `DungeonMasterService` was a monolith that mixed
pipeline orchestration, message persistence, error handling, and step
implementations. Reading it required holding the entire flow in your head
to understand any single part.

The separation means:
- `Pipeline#run_prompt` reads like a linear script: intake,
  then branch, then player_interpreter, then beacon, then mechanics gate, etc.
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

- Intake is a simple assessment — a nano model handles it perfectly
- MechanicalEvaluation requires precise rule interpretation — benefits
  from reasoning models
- Narrate requires creative prose — benefits from large, temperature-
  tunable models
- Context Update is structured JSON — a mini model is plenty

A single model for all steps forces a choice between overpaying for
cheap steps or under-serving expensive ones. Per-step selection lets you
put the budget where it matters.

This also future-proofs for fine-tuning: steps with consistent schemas
(intake, player_interpreter, beacon, context updates) are strong
fine-tuning candidates. You can fine-tune a cheap model on logged examples
and slot it in for one step without affecting others.

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
- MechanicalEvaluation + SanityChecker (capability check + world consistency check) — the full gate
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
peak parallelism (~8 concurrent connections during beacon fan-out).

### 18. Selective context updates (affected + active only)

**Decision:** the Micro Context Update step only includes *relevant*
contexts in its prompt — those flagged as `affected_contexts` by the
beacon plus any that already contain data (active contexts). Contexts
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
2. **Verdict**: a `mutations.travel` object
   (`{ hours_traveled, distance_covered, new_location }`) captures the
   mechanical travel outcome alongside HP/condition mutations.
3. **Context Update**: the prompt explicitly instructs the model to update
   `traversal_context.current_location` from `travel.new_location` and to
   enforce narrative consistency (never carry forward a stale location that
   contradicts the factual outcome).

**Why:** without this chain, travel was a "gap" in the pipeline. The
evaluation step asked for Constitution checks (forced march fatigue) but
never computed how far the player traveled. The verdict step processed the
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
Beacon load domain-specific instructions from separate
partial files (`templates/mechanical_evaluation/_combat.text.erb`,
`templates/beacon/_traversal.text.erb`, etc.) rather than inlining
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

### 25. Beacon (parallel per-domain interpretation)

**Decision:** dispatch six parallel per-domain interpreters that each evaluate
how the sanitized player input affects their domain.

**Why:** asking a single step to handle both intent extraction and domain-specific
rule interpretation overloaded the prompt. Separate beacons give each domain
focused attention — the combat beacon reasons about AoO triggers without being
distracted by traversal movement rules, and so on. Running them in parallel means
wall-clock time equals the slowest single domain, not the sum of all domains.

A PlayerInterpreter step previously sat before the beacons to produce a "pure
restatement" of the input. It was removed (Decision 33) because the beacons
already receive the sanitized input from Intake and perform the real interpretive
work themselves — the restatement added a round-trip with no meaningful quality benefit.

All beacons always run (all six domains). The `interpreter_scope` config
is deprecated — `beacon_domains` always returns all domains.

### 26. SanityChecker (capability + world consistency validation)

**Decision:** rename CapabilityGuardrail to SanityChecker and split it
into two sub-checks:

**A) Capability Check** — validates that the player possesses the spells,
feats, or items they reference. Runs in parallel with MechanicalEvaluation
(only on the mechanics path). Two modes via `guardrail_mode`:
- `"code"` (default): deterministic fuzzy-match against character sheet.
- `"ai"`: AI prompt for holistic validation.

**B) World Consistency Check** — validates that the entities, targets, or
objects the player references actually exist in the current scene. AI-only
step that runs ALWAYS (via the full gate on mechanics path, or standalone
on the non-mechanics path). Receives all non-empty micro-contexts, scene
summary, scene history, and story NPCs.

**Why:** the capability check alone was insufficient. Players could
reference non-existent creatures, NPCs, or objects (e.g., "attack the
goblin" when no goblin exists) and the pipeline would process the action
as valid. The world consistency check closes this gap.

The full gate runs 3 threads in parallel (MechanicalEvaluation + Capability
Check + World Consistency Check) — zero added latency on the happy path.
On the non-mechanics path, the world check runs as a standalone AI call.

Both sub-checks fail open on errors to avoid blocking the player.

**Model note:** the World Consistency Check requires a capable model
(gpt-4o-mini or better). Unlike other steps, this one cannot be
effectively decomposed for budget models.

### 27. Stagehand as code-only synthesis step

**Decision:** make the Stagehand step a pure code step with no AI call.
It sits between Mechanic/Momentum and the output phase (Narrate +
ContextUpdate), packaging results and dispatching the output steps.

**Why:** the original step was an AI call that duplicated work already
done by the Mechanic step. Both received roll results and produced
outcomes — the only difference was one was "factual" and one was
"mechanical." In practice, the model often contradicted itself. By
making Stagehand a code-only routing layer, we eliminate the redundancy
and guarantee consistency.

### 28. Narration mode toggle (parallel vs. subjugated)

**Decision:** the output phase supports two modes via `narration_mode`:
- `"parallel"` (default): Narrate and ContextUpdate run concurrently
- `"subjugated"`: ContextUpdate runs first, then Narrate runs with
  fresh DB state

**Why:** in parallel mode, Narrate and ContextUpdate don't see each
other's output. This is usually fine — Narrate works from the verdict
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

### 30. Social Scene Expansion

**Decision:** add a third resolution mode alongside mechanical (rolls/checks)
and auto-resolve (Momentum) for significant social interactions.

**Why:** Momentum auto-resolves social interactions ("you rented the room")
without player agency. Transactions, negotiations, information-gathering,
and confrontations deserve an immersive NPC scene where the player chooses
how to respond — the same way encounters get expanded into scenes before
combat.

**How:** the Social Beacon flags `expand_scene: true`, CoreResolver calls a
Social Expander AI step instead of TimeKeeper+Momentum, the scene is
returned as `:social_scene` status which breaks the queue like encounters.
The player's response enters a normal new pipeline run.

**Re-expansion guard:** the Social Beacon is instructed not to re-expand if
the `social_context` already has an active interaction. This prevents
infinite scene loops.

**Trade-off accepted:** one extra AI call for actions flagged as significant
social interactions. Justified by player agency — the same tradeoff as
encounter expansion.

### 31. Roll deduplication removed (Principle 17)

**Decision:** remove `deduplicate_rolls!` — the code-side post-merge
deduplication that pattern-matched `[skill, type, dc]` on AI-generated
output to remove duplicate rolls.

**Why:** the dedup was a heuristic fix for an AI-generated problem. When
MechEval produced duplicate Diplomacy DC 10 checks from two different
domain evaluations, code silently removed one. This violated what is now
Design Philosophy Principle 17: code must not heuristically fix AI
problems. The code could only match exact duplicates (same skill, same
DC) — it failed on the harder case of same skill, different DCs, which
required a deeper string-matching heuristic that would compound the
anti-pattern.

**Fix:** the MechEval template now instructs later domain evaluations not
to re-request checks already covered by a previous domain — even at a
different DC. If duplicates still appear, they are logged as warnings
for observability (`warn_duplicate_rolls`) but the rolls array is not
altered. This makes the problem visible rather than silently masking it.

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
directly from Intake (or Sequencer) to the beacons.

**Why:** PlayerInterpreter's only job was producing a "pure restatement" of the
already-sanitized input — one AI call to rephrase what Intake had already cleaned.
The beacons receive that input and do the real interpretive work themselves
(domain classification, mechanics detection, rules routing). The restatement added
latency with no observable quality improvement. The step was pure overhead.

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

**Migration:** started with `unified_evaluation.json`. Other steps will be
migrated incrementally as they are touched.

### 35. UnifiedEvaluation: expand_scene and compute_take_values

**Decision:** add the `expand_scene` signal to the UnifiedEvaluation schema
(social domain only) and replace the misrouted `apply_qualifier_results` call
with a dedicated `compute_take_values` method.

**Why:** `expand_scene` was present in the standard beacon path but missing from
the unified path — social scene expansion would silently fail. The original
`apply_qualifier_results` call passed `intent` (not a qualifier response), which
accidentally worked as a no-op for the qualification overlay but obscured the
actual intent: the unified AI already provides `take_10_eligible` /
`take_20_eligible` per roll, and only the deterministic sheet-math
(`take_10_value` / `take_20_value`) was needed.

`compute_take_values` makes the contract explicit: AI decides eligibility, code
computes the numeric values from the character sheet.

### 36. `AdventureLoop#pipeline_outcome` as the authoritative narration seed

**Decision:** every `CoreResolver` terminal writes the action's narration seed into
`AdventureLoop#data["pipeline_outcome"]` via `batch_update!`. The output phase
(`run_accumulated_output_phase`) assembles the combined seed by querying all
`AdventureLoop` rows for the current `pipeline_run_id` in `sequence_index` order
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
indexed on `pipeline_run_id`. Querying them adds one cheap indexed read and
replaces the entire in-memory accumulation pattern. Any terminal that writes to
the row automatically participates in the combined seed without changes to the
caller.

**Mapping of terminals to `pipeline_outcome`:**

| Path | Value written |
|---|---|
| No-mechanics, no encounter | `momentum_result[:outcome]` — written by `momentum.rb` |
| Mechanics, no encounter | `verdict_result[:outcome]` — written by `finish_resolution` |
| Encounter — awaiting initiative | `[encounter_scene, verdict_outcome].compact.join("\n\n")` |
| Encounter — non-combat | same combined join |
| Social scene | `scene` text from `social_expansion` |

---

## Step Index

For flow and behavioral detail see [pipeline_diagram.md](pipeline_diagram.md). Source files below.

| # | Step | Type | Source |
|---|------|------|--------|
| 1 | **Intake** | AI | `app/services/dungeon_master/steps/intake.rb` |
| 1c | **DM Query** | AI (fast path) | `app/services/dungeon_master/steps/dm_query.rb` |
| 1d | **Sequencer** | AI (toggled) | `app/services/dungeon_master/steps/sequencer.rb` |
| -- | **CoreResolver** (module) | Code orchestration | `app/services/dungeon_master/core_resolver.rb` |
| 3 | **Beacon** | AI (parallel per domain) | `app/services/dungeon_master/steps/beacon.rb` |
| 3u | **UnifiedEvaluation** | AI (replaces beacon+mecheval+rollqualifier) | `app/services/dungeon_master/steps/unified_evaluation.rb` |
| 4a | **MechanicalEvaluation** | AI (loop, parallel with 4b) | `app/services/dungeon_master/steps/mechanical_evaluation.rb` |
| 4c | **RollQualifier** | AI (per domain after 4a) | `app/services/dungeon_master/steps/roll_qualifier.rb` |
| 4b | **SanityChecker** | AI (parallel with 4a) | `app/services/dungeon_master/steps/sanity_checker.rb` |
| 5 | **Mechanic** | AI (mechanical path) | `app/services/dungeon_master/steps/mechanic.rb` |
| 5a | **Momentum** | AI (non-mechanical path) | `app/services/dungeon_master/steps/momentum.rb` |
| 5b | **TimeKeeper** | Code-first, AI fallback | `app/services/dungeon_master/steps/time_keeper.rb` |
| 5c | **Social Expansion** | AI (conditional) | `app/services/dungeon_master/core_resolver.rb` (`resolve_social_scene`) |
| -- | **Harbinger** (utility) | Code + optional AI | `app/services/dungeon_master/utilities/harbinger.rb` |
| -- | **Warmaster** (utility) | Code + optional AI | `app/services/dungeon_master/utilities/warmaster.rb` |
| -- | **GameClock** (utility) | Code-only | `app/services/dungeon_master/utilities/game_clock.rb` |
| 5d | **Chronicler** | AI (conditional) | `app/services/dungeon_master/steps/chronicler.rb` |
| 6 | **Stagehand** | Code-only | `app/services/dungeon_master/steps/stagehand.rb` |
| 7 | **Narrate** | AI | `app/services/dungeon_master/steps/narrate.rb` |
| 8a | **Micro Context Update** | AI (parallel with 8b) | `app/services/dungeon_master/steps/context_update.rb` |
| 8b | **Macro Narrative Update** | AI (conditional) | `app/services/dungeon_master/steps/context_update.rb` |
| -- | **Mutations** | App-side | `app/services/dungeon_master/mutations.rb` |
| -- | **Edge Pipeline** | AI (monolithic alternative) | `app/services/dungeon_master/edge_pipeline.rb` |

---

## Error Handling

All AI steps follow the same error handling pattern:

1. **`TokenBudgetExceededError`**: raised by `AiClient` when the API
   returns `finish_reason: length`. This is a hard error for critical
   steps -- even truncated non-empty responses are rejected. The error is
   logged with `status: "token_budget_exceeded"` and re-raised (for
   intake, player_interpreter, mechanical evaluation, mechanic, momentum, narrate) or
   swallowed with an empty result (for context updates and capability
   guardrail, which are non-critical).

2. **`AiError`**: covers API unreachability, malformed responses, and
   other failures. Same re-raise/swallow pattern as above.

3. **Beacon resilience**: individual Beacon failures
   return `{ affected: false }` for that domain, allowing the pipeline to
   continue with the remaining domains.

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
| `step` | Pipeline step name (intake, beacon, mechanical_evaluation, sanity_checker, sanity_checker_world, mechanic, momentum, social_expansion, chronicler, narrate, micro_context_update, macro_narrative_update, edge_pipeline) |
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
  → CoreResolver#maybe_warmaster_for_encounter
    → Warmaster.initialize_from_encounter!
      → spawn creatures (manifest or fuzzy bestiary + dynamic fallback)
      → roll creature initiative
      → return :awaiting_initiative
  → Pipeline pauses, sends initiative_request to player
```

### Path B — Narrative-originated combat

```
Beacon (combat domain) → transition: "combat_started", combatants: [...]
  → Stagehand#maybe_initialize_combat
    → Warmaster.initialize_from_names!
      → fuzzy bestiary lookup + dynamic fallback
      → roll creature initiative
      → return :awaiting_initiative
  → Pipeline pauses, sends initiative_request to player
```

### Initiative Resolution

1. Player submits initiative → `finalize_combat!` → `combat_context` populated → pipeline continues
2. Player ignores prompt and sends new action → `auto_finalize_pending_initiative!` →
   auto-roll (d20 + DEX mod) → `finalize_combat!` → new action processed in combat context

### Guards

- `combat_active?` check in `TimeKeeper#consult_harbinger_if_needed` prevents encounters during combat
- `stagehand_combat_active?` check prevents re-initialization when combat is already active
- Combat beacon partial shows active participants, preventing AI from re-signaling `combat_started`

### Creature Resolution Chain

1. **Manifest** (if `EncounterTableEntry#has_manifest?`): deterministic bestiary lookup by ID
2. **Fuzzy bestiary match**: singularize → exact LOWER → ILIKE → id fallback
3. **Dynamic fallback** (per `creature_creation_fallback` config):
   - `"ai"`: AI generates PF1e stat block via `creature_generation` step
   - `"template"`: tier-scaled generic stat block
   - `"none"`: creature not created

See `app/services/dungeon_master/utilities/warmaster.rb` for implementation detail.

---

## Social Scene Lifecycle

When a significant social interaction is detected, the pipeline expands it
into an immersive NPC scene rather than auto-resolving via Momentum.

### Flow

```
Beacon (social domain) → expand_scene: true
  → CoreResolver#resolve_social_scene
    → Social Expander AI call (social_expansion template)
    → Scene data written to @loop
    → return :social_scene
  → Pipeline breaks queue (like encounter)
  → Output phase: narrate + context update
  → Player sees scene, responds freely
  → New pipeline run (normal flow — may go mechanical or Momentum)
```

### Re-expansion Guard

The Social Beacon is instructed to NOT flag `expand_scene: true` when the
`social_context` already contains an active NPC interaction. This prevents
infinite scene loops. The player's response resolves through Momentum
(auto-resolve) or the mechanical path (if they attempt something requiring
a skill check), ensuring natural conclusion.

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

All pipeline behavior is configurable through `DmConfig` (admin UI at
`/admin/dm_config`):

| Setting | Default | Affects |
|---|---|---|
| `danger_threshold` | `30` | Intake: danger score cutoff (0-100) |
| `verbose` | `false` | Narrate: enables unconstrained response length |
| `pacing_words_min` | `40` | Narrate: minimum word count target when verbose is off |
| `pacing_words_max` | `120` | Narrate: maximum word count target when verbose is off |
| `chronicler_tone_direction` | `false` | Chronicler: when true, includes atmosphere/tone guidance in DM Brief |
| `temperature` | `0.8` | All steps: creativity/randomness (non-reasoning models only) |
| `model` | `gpt-4o-mini` | Default model for all steps |
| `step_models[step]` | `{}` | Per-step model override |
| `token_budgets[step]` | (see below) | Per-step max completion tokens |
| `action_queue` | `true` | When true, compound player inputs are split into discrete sequential actions by the Sequencer step |
| `evaluation_mode` | `"unified"` | `"unified"` (single AI call for all domains) or `"standard"` (legacy: 6 parallel beacons + sequential mech eval) |
| `pipeline_mode` | `"budget"` | `"budget"` (multi-step) or `"edge"` (single-call) |
| `interpreter_scope` | *(deprecated)* | All beacons always run; this setting has no effect |
| `guardrail_mode` | `"code"` | `"code"` (deterministic) or `"ai"` (prompt-based) |
| `narration_mode` | `"parallel"` | `"parallel"` (concurrent) or `"subjugated"` (sequential) |
| `async_pipeline` | `false` | When true, pipeline runs in Sidekiq with ActionCable delivery |
| `creature_creation_fallback` | `"ai"` | `"ai"` (bestiary + AI gen), `"template"` (bestiary + generic stats), `"none"` |
| `scene_history_depth` | `10` | Number of scene summaries retained for world consistency checks |

### Default token budgets

| Step | Budget |
|---|---|
| `intake` | 400 |
| `dm_query` | 300 |
| `player_interpreter` | 200 |
| `beacon` | 400 |
| `mechanical_evaluation` | 500 |
| `sanity_checker` | 300 |
| `sanity_checker_world` | 500 |
| `mechanic` | 600 |
| `momentum` | 500 |
| `social_expansion` | 500 |
| `time_keeper` | 300 |
| `chronicler` | 500 |
| `narrate` | 800 |
| `micro_context_update` | 800 |
| `macro_narrative_update` | 500 |
| `creature_generation` | 600 |
| `edge_pipeline` | 2000 |

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
