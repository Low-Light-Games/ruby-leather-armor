# Dungeon Master Pipeline — Step Reference

Design document describing the AI Dungeon Master pipeline: what each step
does, what it receives, what it produces, and how the steps connect.

---

## Design Decisions

Architectural choices that shaped the pipeline, why each alternative was
rejected, and what trade-offs we accepted.

### 1. Sequential pipeline of small prompts vs. single monolithic prompt

**Decision:** break the AI interaction into 6+ focused calls instead of
one large "do everything" prompt.

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
- **Model selection is locked.** Some tasks (ruling) benefit from
  reasoning models; others (narration) benefit from creative models.
  A single call forces one model for everything.

**Trade-off accepted:** higher latency (multiple serial round-trips) and
slightly higher total token usage (repeated context in each prompt).
We accepted this because correctness and debuggability matter more than
speed for a turn-based game, and per-step model selection recovers most
of the cost overhead by using cheap models on cheap steps.

**Alternative rejected:** a two-call split (mechanics + narration) was
considered but still left the mechanics call too overloaded. The 6-step
design emerged from iteratively identifying which sub-tasks degraded
when combined.

### 2. Three micro-contexts instead of a single context blob

**Decision:** maintain separate `traversal_context`, `combat_context`,
and `social_context` JSONB fields on the Adventure, each with its own
schema.

**Why:** Pathfinder 1e naturally decomposes into these three domains.
A player action can affect multiple domains simultaneously ("I jump into
the sacred lake to escape my attackers" touches combat, traversal, and
social), and each domain has fundamentally different state shapes:

- Combat: turn order, round number, participant HP, conditions, positions
- Traversal: location, terrain, weather, exits, nearby NPCs
- Social: NPC attitudes, conversation state, persuasion progress

A single blob would force the AI to reason about all three schemas in
every call, even when only one is relevant. Separate contexts let the
Ruling step receive *only the domain it's adjudicating*, keeping the
prompt focused and the output structured.

**Trade-off accepted:** the Context Update step must output all three
contexts even when only one changed. This is minor overhead — the model
returns unchanged contexts verbatim.

**Alternative rejected:** a single `game_state` JSON blob was the initial
design. It produced inconsistent schemas (the model would invent different
field names across turns) and made it hard to scope the Ruling step to
one domain.

### 3. App-side NPC roll resolution

**Decision:** the application rolls dice for NPCs using `rand(1..20)`,
not the AI.

**Why:** if the AI resolves NPC rolls, it can:
- Fudge results to fit a narrative it wants to tell
- Produce results that don't match the NPC's actual stat block
- Be inconsistent about which modifiers it applies

By having the app roll deterministically using the modifiers specified
by the Ruling step (which references real `CreatureSheet` data), we
guarantee that NPC combat is mechanically honest. The Ruling step decides
*what* the NPC does and *what modifier* applies; the app decides *what
the die shows*.

**Trade-off accepted:** the Evaluate step receives NPC results as text
("Goblin A rolled 14 + 3 = 17 vs AC 15: HIT") rather than structured
data. This is slightly more work to parse but keeps the evaluation
prompt human-readable.

**Player rolls are different:** the player submits their own roll results
via the UI. This is a deliberate engagement choice — rolling dice is part
of the tabletop experience. The app trusts the player's reported values
(honor system, as in a real tabletop game).

### 4. Ruling loop with summary chaining

**Decision:** run the Ruling step once per affected context, passing
previous ruling summaries to each subsequent iteration.

**Why:** asking the AI to adjudicate combat mechanics, traversal skill
checks, and social consequences in a single prompt produces unreliable
results. The model loses track of which rules apply where — it might
apply combat attack-of-opportunity rules to a social interaction, or
forget a traversal check because it was focused on combat.

By looping with summaries, each call is scoped to one domain ("you are
adjudicating COMBAT only") while retaining cross-context awareness
("here's what already happened in TRAVERSAL"). The summary chaining
ensures that the social ruling knows the player jumped into the sacred
lake (from the traversal ruling) without having to reason about swim
checks itself.

**Trade-off accepted:** multi-context actions cost 2-3x the ruling
budget. This is acceptable because multi-context actions are less common
than single-context ones, and the accuracy improvement is dramatic.

**Alternative rejected:** forking the entire pipeline per context was
considered but would have duplicated evaluation, narration, and context
updates — far more expensive and harder to merge into a coherent
narrative.

### 5. Evaluate before narrate (mechanics-first ordering)

**Decision:** determine the factual mechanical outcome before writing
any narrative.

**Why:** if the model narrates and evaluates simultaneously, narrative
bias corrupts mechanical accuracy. The model might write a dramatic
"the goblin collapses!" moment and then produce mutations showing the
goblin at 3 HP — or vice versa, produce correct mutations but a
narrative that contradicts them.

By evaluating first, the Narrate step receives a factual outcome it must
faithfully narrate. It cannot contradict the mechanics because it didn't
determine them.

**Trade-off accepted:** two AI calls where one might suffice. The cost
is justified by correctness — mechanical errors in a Pathfinder game
(wrong HP, missed saves, ignored conditions) directly degrade the
player's trust in the DM.

### 6. Structured mutations instead of natural language

**Decision:** the Evaluate step outputs explicit structured mutations
(`{ "hp_change": -8 }`) rather than prose ("the goblin takes 8 damage").

**Why:** the app must apply these changes to the database. If the AI
produces natural language, the app must parse it — "takes 8 damage",
"loses 8 hit points", "is dealt 8 points of damage" all mean the same
thing but require NLP to extract. Structured JSON is unambiguous and
directly actionable.

This also makes mutations auditable. Every `AiLog` entry for an
`evaluate` step contains the exact mutations that were applied,
traceable back to the rolls and rulings that produced them.

### 7. Rules fetched by slug from a YAML index

**Decision:** rules are stored as YAML files keyed by slug. The Intent
step requests rules by slug, and the app fetches the corresponding text
to inject into the Ruling prompt.

**Why:** LLMs hallucinate rules. Pathfinder 1e has thousands of rules
with subtle interactions (grapple, combat maneuvers, spell resistance,
damage reduction). If the model recites rules from memory, it will get
details wrong — particularly for less common rules.

By giving the model a manifest of available rules (slug + short
description) and having it request what it needs, we ensure:
- The Ruling step receives accurate rule text, not hallucinated rules
- The rules can be updated or corrected without retraining
- We can audit which rules were used for each ruling

**Trade-off accepted:** the Intent step must correctly identify which
rules are relevant. If it misses a rule, the Ruling step won't have it.
This is mitigated by providing the full manifest — the model sees all
available rules and can request any combination.

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

**Decision:** when Triage classifies the input as `dm_query`, skip the
entire action pipeline and route to a dedicated DM Query step.

**Why:** many player messages are questions ("How does grappling work?",
"What's in my inventory?", "What can I see?"). These don't advance the
game state and shouldn't trigger mechanical resolution, narrative
generation, or context updates.

Routing questions through the full pipeline would:
- Waste 5+ AI calls on a non-action
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
- `Pipeline#run_prompt` reads like a linear script: triage, then branch,
  then intent, then ruling loop, etc. A developer can read the full flow
  in ~30 lines.
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

- Triage is simple classification — a nano model handles it perfectly
- Ruling requires precise rule interpretation — benefits from reasoning
- Narrate requires creative prose — benefits from large, temperature-
  tunable models
- Context Update is structured JSON — a mini model is plenty

A single model for all steps forces a choice between overpaying for
cheap steps or under-serving expensive ones. Per-step selection lets you
put the budget where it matters.

This also future-proofs for fine-tuning: steps with consistent schemas
(triage, intent, context updates) are strong fine-tuning candidates. You
can fine-tune a cheap model on logged examples and slot it in for one
step without affecting others.

**Trade-off accepted:** more configuration complexity. The admin UI
mitigates this with per-step suggestions, model cost display, and
sensible defaults.

### 13. Reasoning field on all AI outputs

**Decision:** every pipeline step's JSON schema includes a `reasoning`
field that the model must populate.

**Why:** when something goes wrong (incorrect ruling, bad evaluation,
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
- A ruling with `player_rolls` cut off mid-array
- An evaluation with mutations missing NPC entries
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

**Why:** error messages like "Token budget exceeded on 'triage' step
(budget: 300)" leak system internals to the player, breaking immersion
and potentially exposing configuration details. The player doesn't need
to know about token budgets, pipeline steps, or API errors — they need
to know the DM fumbled and they should try again.

Admins have full visibility through `AiLog` records and the admin UI.

### 16. Context update resilience (errors swallowed)

**Decision:** steps 6a (Micro Context Update) and 6b (Macro Narrative
Update) rescue all errors and return empty hashes instead of failing
the pipeline.

**Why:** context updates are important but not critical to the current
turn. If the micro context update fails:
- The player still sees their narrative (it was generated before context
  updates ran)
- Future prompts may be slightly degraded (stale context) but still
  functional

Failing the entire turn because a context update errored would be
disproportionate — the player would see an error message for a turn that
was otherwise fully resolved and narrated.

The error is still logged, so the admin knows context updates are
failing and can investigate.

### 17. Parallel execution of context updates

**Decision:** steps 6a and 6b run concurrently in Ruby threads.

**Why:** they write to different database fields (`traversal_context` /
`combat_context` / `social_context` vs. `story_summary`) and have no
data dependencies on each other. Running them in parallel saves one full
AI round-trip of latency on turns where the macro update fires.

**Trade-off accepted:** Ruby thread complexity. Mitigated by keeping the
threads simple (each runs one AI call and one database write) with
error isolation (each thread rescues independently).

---

## Architecture Overview

Every player message flows through `DungeonMasterService`, a thin
orchestrator that handles message persistence and error handling. The
actual pipeline logic lives in `DungeonMaster::Pipeline`, which runs
steps sequentially and returns a result hash. The service maps that
result to persisted `AdventureMessage` records.

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
│   DungeonMaster::Pipeline    │  Pure pipeline logic
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
┌─────────┐    danger >= threshold
│ TRIAGE  │ ───────────────────────► { action: :rejected }
└────┬────┘
     │
     │  category == "dm_query"
     ├──────────────────────────────► DM QUERY ──► { action: :dm_query }
     │
     ▼
┌─────────┐    needs_mechanics == false
│ INTENT  │ ───────────────────────► NARRATE ──► CONTEXT UPDATES
└────┬────┘                                          │
     │  needs_mechanics == true                      ▼
     ▼                                    { action: :narrated }
┌──────────────┐
│ RULING LOOP  │  (one pass per affected context)
└──────┬───────┘
       │
       │  player rolls needed?
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
│  2. EVALUATE (AI)                        │
│  3. Apply mutations (app-side)           │
│  4. NARRATE (AI)                         │
│  5. CONTEXT UPDATES (AI, parallel)       │
└──────────────────────────────────────────┘
                    │
                    ▼
          { action: :narrated }
```

---

## Step 1: Triage

**File:** `app/services/dungeon_master/steps/triage.rb`
**Template:** `app/services/dungeon_master/templates/triage.text.erb`
**Pipeline step name:** `triage`

### Purpose

Combined security filter and action classifier. This is the first thing
that happens to every player message. It has two jobs:

1. **Sanitization** — scores the input for danger (prompt injection,
   meta-gaming, out-of-character manipulation) on a 0-100 scale. If the
   score meets or exceeds the configurable `sanitization_threshold` in
   `DmConfig`, the pipeline rejects the input immediately and no further
   AI calls are made.

2. **Classification** — categorizes the input into exactly one of:
   `combat`, `traversal`, `social`, `roll_request`, or `dm_query`. This
   determines which branch the pipeline follows.

### Input

| Field | Source |
|---|---|
| System prompt | `triage.text.erb` (static, no dynamic bindings) |
| User message | Raw player input (unmodified) |

### Output (JSON)

```json
{
  "danger_score": 0,
  "sanitized_input": "cleaned version of the player's input",
  "reason": "explanation of danger assessment, null if safe",
  "category": "traversal",
  "classification_reasoning": "why this category was chosen"
}
```

### App-side post-processing

- If `danger_score >= sanitization_threshold`: pipeline returns
  `{ action: :rejected }` immediately. The service persists a
  `sanitization_fail` message.
- The `category` is normalized against the allowed list; unknown
  categories fall back to `dm_query`.
- The `sanitized_input` (not the raw input) is forwarded to all
  subsequent steps.

### Design rationale

Triage is intentionally the cheapest, simplest step. It's a gatekeeper:
fast to execute, cheap to run, and its failure mode (rejecting safe input)
is far less damaging than letting malicious input through. By combining
sanitization and classification in one call, we avoid a redundant second
AI call for classification on its own — the model reads the input once
and does both jobs.

---

## Step 1b: DM Query (fast path)

**File:** `app/services/dungeon_master/steps/dm_query.rb`
**Template:** `app/services/dungeon_master/templates/dm_query.text.erb`
**Pipeline step name:** `dm_query`

### Purpose

Answers out-of-character player questions ("What are my known spells?",
"How does grappling work?", "What can I see around me?") without
advancing the scene or triggering any mechanics.

This is a **fast path**: when Triage classifies the input as `dm_query`,
the pipeline skips Intent, Ruling, Evaluate, Narrate, and Context Updates
entirely. The question goes in, an answer comes out, nothing changes.

### Input

| Field | Source |
|---|---|
| System prompt | `dm_query.text.erb` bound with: story title, story summary, formatted micro-contexts, DM guidance text |
| User message | Sanitized player input (from Triage) |

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
full 6-step pipeline would be wasteful and could cause unintended side
effects (context updates reflecting a non-event). The fast path keeps
query latency low and cost minimal.

---

## Step 2: Intent

**File:** `app/services/dungeon_master/steps/intent.rb`
**Template:** `app/services/dungeon_master/templates/intent.text.erb`
**Pipeline step name:** `intent`

### Purpose

Interprets what the player is trying to do. Restates the intention
clearly, determines whether mechanical resolution is needed, identifies
which game contexts are affected, and requests relevant Pathfinder rules
by slug.

### Input

| Field | Source |
|---|---|
| System prompt | `intent.text.erb` bound with: formatted micro-contexts (traversal, combat, social), rules manifest (available rule slugs with descriptions) |
| User message | Sanitized player input (from Triage) |

### Output (JSON)

```json
{
  "intention": "Clear restatement of what the player wants to do",
  "needs_mechanics": true,
  "affected_contexts": ["combat", "traversal"],
  "primary_context": "combat",
  "rules_needed": ["attack_resolution", "attack_of_opportunity"],
  "transition": null,
  "macro_significant": false,
  "reasoning": "Brief explanation of intent interpretation"
}
```

### Key fields explained

- **`needs_mechanics`**: `false` for purely narrative actions (looking
  around, greeting someone). When false, the pipeline skips Ruling and
  Evaluate, going straight to Narrate.
- **`affected_contexts`**: drives the Ruling loop. If multiple contexts
  are listed (e.g. `["combat", "traversal"]` for "I leap across the
  chasm to escape my attackers"), the Ruling step runs once per context.
- **`primary_context`**: determines the order of the Ruling loop. The
  primary context is always processed first, so subsequent rulings can
  reference its summary.
- **`rules_needed`**: slug identifiers from the rules YAML index. The
  app fetches the corresponding rule text and injects it into the Ruling
  prompt. This keeps the AI from inventing rules.
- **`transition`**: signals lifecycle changes like `"combat_started"`,
  `"combat_ended"`, or `"social_to_combat"`. Currently used for logging;
  may drive app-side state machine in the future.
- **`macro_significant`**: when `true`, the Macro Narrative Update step
  fires after narration. Should only be `true` for major story beats
  (boss defeated, quest completed), not routine actions.

### Design rationale

Intent is the pipeline's routing decision. By cleanly separating "what
does the player want?" from "what are the rules?" and "what happens?",
each subsequent step receives a focused, well-defined task. The rules
manifest is passed to the model so it can request rules by slug rather
than reciting them from memory (which would produce hallucinated rules).

---

## Step 3: Ruling Loop

**File:** `app/services/dungeon_master/steps/ruling.rb`
**Template:** `app/services/dungeon_master/templates/ruling.text.erb`
**Pipeline step name:** `ruling`

### Purpose

The mechanical core of the pipeline. Determines what dice rolls are
needed, what NPC actions occur, and what automatic consequences follow —
all within the framework of Pathfinder 1e rules.

### The loop

This step runs **once per affected context** identified by the Intent
step. If the player's action affects combat and traversal, the ruling
runs twice: first for the primary context, then for the secondary one.

Each iteration receives the summaries of all preceding rulings. This is
how the pipeline handles multi-context actions:

```
Iteration 1: Ruling for COMBAT
  → "Player attacks Goblin A, provoking AoO from Goblin B"
  → ruling_summary: "[COMBAT] Player swings at Goblin A..."

Iteration 2: Ruling for TRAVERSAL
  → receives previous summary: "[COMBAT] Player swings at Goblin A..."
  → "Player also attempts to move 10 feet toward the door"
  → ruling_summary: "[TRAVERSAL] Player moves toward the door..."
```

### Input (per iteration)

| Field | Source |
|---|---|
| System prompt | `ruling.text.erb` bound with: domain name, player character block (domain-relevant stats), micro-context for this domain, creature/NPC stat blocks, previous ruling summaries, fetched rules text |
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
    { "target": "Village Elder", "effect": "attitude_shift", "from": "friendly", "to": "unfriendly", "reason": "desecrated the sacred lake" }
  ],
  "ruling_summary": "Brief mechanical summary of what happens in this domain",
  "reasoning": "Brief explanation of rules applied"
}
```

### App-side post-processing

After all iterations complete, rulings are **merged**:

```ruby
{
  player_rolls:    rulings.flat_map { |r| r[:player_rolls] },
  npc_actions:     rulings.flat_map { |r| r[:npc_actions] },
  consequences:    rulings.flat_map { |r| r[:consequences] },
  ruling_summaries: rulings.map { |r| "[#{r[:domain]}] #{r[:ruling_summary]}" }
}
```

If `player_rolls` is non-empty, the pipeline **pauses** and returns
`{ action: :awaiting_rolls }`. The merged data is persisted in the
`roll_request` message's metadata so the pipeline can resume later.

If no player rolls are needed (e.g. only NPC actions and consequences),
the pipeline proceeds directly to Resolution Flow.

### Design rationale

The ruling step is deliberately scoped to one domain per call. Asking the
AI to simultaneously adjudicate combat mechanics, traversal skill checks,
and social consequences in a single prompt produces unreliable results —
the model loses track of which rules apply where. By looping with summary
chaining, each call stays focused while retaining cross-context awareness.

The `player_rolls` / `npc_actions` split is also deliberate: player rolls
are resolved by the player (submitted via UI), while NPC rolls are
resolved deterministically by the app. This keeps the player engaged
(they roll their own dice) while ensuring NPC mechanics are consistent
and not hand-waved by the AI.

---

## App-side: NPC Roll Resolution

**File:** `app/services/dungeon_master/mutations.rb` (`resolve_npc_actions`)

### Purpose

Rolls dice for NPC actions deterministically. This is **not** an AI step —
it's pure application logic using `rand(1..20)`.

### Input

The merged `npc_actions` array from the Ruling step.

### Logic

For each NPC action:
1. Roll d20
2. Add the NPC's modifier (from the ruling)
3. Compare against the player's AC (from the character sheet)
4. Produce a textual result: `"Goblin A attack -> rolled 14 + 3 = 17 vs AC 15: HIT"`

### Output

A text block of all NPC roll results, which feeds into the Evaluate step.

### Design rationale

Having the app roll for NPCs ensures consistency and prevents the AI from
fudging results. The rolls use the modifiers specified by the ruling
(which referenced actual creature stat blocks), keeping the mechanical
resolution grounded in real numbers.

---

## App-side: Player Roll Submission

When the pipeline returns `{ action: :awaiting_rolls }`, the UI presents
the player with the required rolls. The player submits their results,
which re-enter the pipeline through `DungeonMasterService#process_roll_result`.

This calls `Pipeline#run_rolls`, which:
1. Restores the intent and merged ruling data from the persisted
   `roll_request` message metadata
2. Feeds everything into the Resolution Flow

---

## Step 4: Evaluate

**File:** `app/services/dungeon_master/steps/evaluate.rb`
**Template:** `app/services/dungeon_master/templates/evaluate.text.erb`
**Pipeline step name:** `evaluate`

### Purpose

Takes the dice results (both player and NPC), the ruling summaries, and
the character sheet, and determines the factual mechanical outcome. Did
the attack hit? How much damage? Did the save succeed? What conditions
apply?

The output is factual, not narrative. It produces structured **mutations**
that the app applies to the database.

### Input

| Field | Source |
|---|---|
| System prompt | `evaluate.text.erb` bound with: full player character block, ruling summaries text, combined roll results (player + NPC), pending consequences, formatted micro-contexts |
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
    "spells_used": ["Magic Missile"]
  }
}
```

### App-side post-processing

The `mutations` hash is applied by `DungeonMaster::Mutations#apply_mutations`:
- **Player HP**: clamped between `-constitution` (death threshold) and
  `max_hp`
- **NPC HP**: clamped between 0 and `max_hp`
- **NPC attitude changes**: validated against `CreatureSheet::ATTITUDES`
  before persisting
- **Conditions, items, spells**: logged but not yet mechanically enforced
  (future enhancement)

The `outcome` text (not the mutations) is forwarded to the Narrate step.

### Design rationale

Separating evaluation from narration ensures the mechanical outcome is
determined objectively before the narrative is written. If the AI narrated
and evaluated simultaneously, it could write a dramatic "the goblin falls!"
moment and then produce mutations that say the goblin still has 3 HP.
By evaluating first, the narrative faithfully reflects what actually
happened.

The mutations structure is intentionally explicit (HP changes, not "takes
damage") so the app can apply them without interpreting natural language.

---

## Step 5: Narrate

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
| System prompt | `narrate.text.erb` bound with: story title, story premise, story summary, formatted micro-contexts, mechanical outcome text (from Evaluate, or nil), pacing instructions (from DmConfig verbose/word count settings), directed play instructions (if `directed_dm` is enabled on the Adventure) |
| User message | The outcome text, or "Narrate the current scene." if no mechanical outcome |

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
  that the adventure has concluded. The AI is instructed to only set
  this to `true` when the story reaches a genuinely satisfying
  conclusion.

### Pacing control

The narrate template receives `pacing_text` which varies based on
DmConfig settings:
- **Verbose off**: instructs the DM to keep responses to 1-2 paragraphs
  within the configured word range (default: min 80, max 200 words)
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
determine hit/miss, or decide outcomes — that was done in Evaluate.

This separation means:
1. The narrative can never contradict the mechanics
2. You can swap the narration model independently (e.g. use a creative
   model here and a cheap model for evaluation)
3. Pacing and style controls affect only the narrative, not the
   mechanical resolution

---

## Step 6a: Micro Context Update

**File:** `app/services/dungeon_master/steps/context_update.rb`
**Template:** `app/services/dungeon_master/templates/micro_context_update.text.erb`
**Pipeline step name:** `micro_context_update`

### Purpose

Updates the three micro-context JSONB fields on the Adventure model
(`traversal_context`, `combat_context`, `social_context`) to reflect
what just happened.

### Input

| Field | Source |
|---|---|
| System prompt | `micro_context_update.text.erb` bound with: the narration text, mutations JSON (from Evaluate), current values of all three context fields |
| User message | "Update contexts based on the above." |

### Output (JSON)

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
  "reasoning": "Combat continues, traversal updated to lake, social tension with Elder"
}
```

### Context field schemas

**Traversal context** tracks:
- `current_location`, `destination`, `terrain`, `weather`, `time_of_day`
- `nearby_npcs`, `points_of_interest`, `exits`

**Combat context** tracks:
- `active` (boolean), `round`, `current_turn`, `turn_order`
- `participants` (name, hp, conditions, position)
- `terrain_notes`, `active_effects`

**Social context** tracks:
- `scene`, `npcs_present` (name, role, attitude, notes)
- `conversation_state`, `stakes`, `persuasion_progress`

### App-side post-processing

- Each non-empty context in the response updates the corresponding
  Adventure JSONB field
- If `new_creatures` is present, the app performs a **bestiary lookup**
  for each name. If a matching `BestiaryEntry` exists (OGL/SRD compliant),
  a `CreatureSheet` is created with deterministically rolled HP. If no
  match is found, a warning is logged but the pipeline continues.

### Design rationale

Micro-contexts are the pipeline's short-term memory. Every AI call
(triage excepted) receives them as context. Keeping them accurate is
critical — a stale combat context that still lists a defeated enemy will
cause the Ruling step to generate attacks from a corpse.

By having a dedicated step for context updates (rather than asking each
step to update context as a side effect), we ensure:
1. Updates happen exactly once, after all mechanics are resolved
2. The model sees the final narrative (not intermediate state)
3. Context update quality can be tuned independently (different model,
   different budget)

---

## Step 6b: Macro Narrative Update

**File:** `app/services/dungeon_master/steps/context_update.rb`
**Template:** `app/services/dungeon_master/templates/macro_narrative_update.text.erb`
**Pipeline step name:** `macro_narrative_update`

### Purpose

Updates the adventure's `story_summary` field — the high-level "story so
far" that carries across the entire adventure. Only runs when the Intent
step flagged the action as `macro_significant`.

### Input

| Field | Source |
|---|---|
| System prompt | `macro_narrative_update.text.erb` bound with: story hook/title, current story summary, latest narrative text |
| User message | "Update the story summary." |

### Output (JSON)

```json
{
  "story_summary": "Updated story-so-far summary (3-8 sentences)",
  "reasoning": "What was added/changed"
}
```

### Execution

Steps 6a and 6b run **in parallel** (Ruby threads). The macro update is
conditional — it only fires when `macro_significant` is true. If both
run, they execute concurrently since they write to different fields.

### Design rationale

The story summary feeds into every future Narrate prompt, giving the DM
long-term memory. But updating it on every turn would cause bloat and
inaccuracy. The `macro_significant` flag from Intent acts as a filter:
only story-changing events (quest completion, boss defeat, plot
revelation) trigger an update.

The template explicitly instructs the model to write only about events
that have already occurred — preventing it from leaking future plot
points or unrevealed secrets into the summary.

---

## App-side: Mutation Application

**File:** `app/services/dungeon_master/mutations.rb`

This module handles all non-AI state changes between the Evaluate and
Narrate steps.

### `apply_mutations(mutations)`

Applies the structured mutations hash from the Evaluate step:

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
   returns `finish_reason: length`. This is a hard error for all steps —
   even truncated non-empty responses are rejected. The error is logged
   with `status: "token_budget_exceeded"` and re-raised (for triage,
   intent, ruling, evaluate, narrate) or swallowed with an empty result
   (for context updates, which are non-critical).

2. **`AiError`**: covers API unreachability, malformed responses, and
   other failures. Same re-raise/swallow pattern as above.

3. **Context update resilience**: Steps 6a and 6b rescue all errors and
   return empty hashes rather than failing the pipeline. This is
   intentional — a failed context update degrades future prompts but
   doesn't break the current turn for the player.

At the service level, all errors are caught and translated into a
generic player-facing message: *"The Dungeon Master is momentarily
distracted..."*. Technical details are logged only.

---

## Logging

Every AI call produces an `AiLog` record containing:

| Field | Description |
|---|---|
| `step` | Pipeline step name (triage, intent, ruling, etc.) |
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

| Setting | Affects |
|---|---|
| `sanitization_threshold` | Triage: danger score cutoff (0-100) |
| `verbose` | Narrate: enables unconstrained response length |
| `pacing_words_min/max` | Narrate: word count targets when verbose is off |
| `temperature` | All steps: creativity/randomness (non-reasoning models only) |
| `model` | Default model for all steps |
| `step_models[step]` | Per-step model override |
| `token_budgets[step]` | Per-step max completion tokens |

See `docs/pipeline_model_selection.md` for detailed model recommendations
per step.
