# Pipeline Model Selection Guide

Developer reference for choosing OpenAI models per pipeline step.
Each player message triggers a sequence of AI calls (the pipeline). Because
steps vary drastically in complexity, a single model for every call is
wasteful — cheap steps subsidize expensive ones, or quality suffers where it
matters most.

This guide groups available models into tiers, explains what each pipeline
step actually asks the model to do, and recommends where to spend and where
to save. See [Design Philosophy](design_philosophy.md) for the principles
behind these choices (especially *Structured decomposition over model
reasoning* and *When in doubt, add a toggle*).

---

## Model Tier Reference

Prices are **per 1 million tokens** (input / output).

### Nano tier — dirt-cheap, low latency


| Model        | Input | Output | Reasoning | Temp |
| ------------ | ----- | ------ | --------- | ---- |
| gpt-4.1-nano | $0.10 | $0.40  | No        | Yes  |
| gpt-5-nano   | $0.05 | $0.40  | Yes       | No   |


Best for: classification, simple JSON output, short-answer tasks.
These models are extremely fast and cheap enough that you can call them
many times per player turn without noticing the cost.

### Mini tier — balanced cost/capability


| Model        | Input | Output | Reasoning | Temp |
| ------------ | ----- | ------ | --------- | ---- |
| gpt-4o-mini  | $0.15 | $0.60  | No        | Yes  |
| gpt-4.1-mini | $0.40 | $1.60  | No        | Yes  |
| gpt-5-mini   | $0.25 | $2.00  | Yes       | No   |
| o3-mini      | $1.10 | $4.40  | Yes       | No   |
| o4-mini      | $1.10 | $4.40  | Yes       | No   |


Best for: structured reasoning, moderate rule application, context updates.
Mini models sit in a sweet spot: smart enough to follow complex instructions
and produce well-formed JSON, cheap enough to use on multiple steps.

### Full tier — highest non-pro capability


| Model   | Input | Output | Reasoning | Temp |
| ------- | ----- | ------ | --------- | ---- |
| gpt-4o  | $2.50 | $10.00 | No        | Yes  |
| gpt-4.1 | $2.00 | $8.00  | No        | Yes  |
| gpt-5   | $1.25 | $10.00 | Yes       | No   |
| gpt-5.1 | $1.25 | $10.00 | Yes       | No   |
| gpt-5.2 | $1.75 | $14.00 | Yes       | No   |
| o3      | $2.00 | $8.00  | Yes       | No   |


Best for: creative writing, complex multi-factor evaluation, narrative.
Use these where quality directly impacts the player experience.

### Pro tier — maximum compute (use sparingly)


| Model       | Input   | Output  | Reasoning | Temp |
| ----------- | ------- | ------- | --------- | ---- |
| gpt-5-pro   | $15.00  | $120.00 | Yes       | No   |
| gpt-5.2-pro | $21.00  | $168.00 | Yes       | No   |
| o3-pro      | $20.00  | $80.00  | Yes       | No   |
| o1-pro      | $150.00 | $600.00 | Yes       | No   |


Best for: nothing in this pipeline, realistically. A single player turn
could cost dollars. Listed for completeness; only consider for offline
batch analysis or debugging a particularly gnarly ruling.

### Legacy tier — avoid for new deployments


| Model         | Input  | Output | Reasoning | Temp |
| ------------- | ------ | ------ | --------- | ---- |
| gpt-4-turbo   | $10.00 | $30.00 | No        | Yes  |
| gpt-4         | $30.00 | $60.00 | No        | Yes  |
| gpt-3.5-turbo | $0.50  | $1.50  | No        | Yes  |
| o1            | $15.00 | $60.00 | Yes       | No   |
| o1-mini       | $1.10  | $4.40  | Yes       | No   |


These are superseded by newer models that are both cheaper and smarter.
gpt-3.5-turbo in particular will struggle with Pathfinder rules and
multi-context structured JSON. o1/o1-mini are deprecated in favor of
o3/o4-mini.

---

## Step-by-step Recommendations

### 1a. Sanitize

**What it does:** security filter. Scores the player input on a 0-100
danger scale for prompt injection, jailbreaking, harassment, and
meta-gaming. Can kill the pipeline if the score exceeds the configured
`sanitization_threshold`. Runs in parallel with Classify.

**Cognitive demand:** very low. Pattern matching on a single sentence.

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

**Acceptable:** gpt-4.1-mini, gpt-5-mini

**Avoid:** any full or pro model. This is pure pattern detection.

**Token budget:** 300 (non-reasoning) / 1200 (reasoning).

---

### 1b. Classify

**What it does:** buckets the player input into one game domain (combat,
traversal, social, exploration, rest, inventory, dm_query). Runs in
parallel with Sanitize. Output is a small JSON blob with a `category` field.

**Cognitive demand:** very low. Single-label classification.

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

**Acceptable:** gpt-4.1-mini, gpt-5-mini

**Avoid:** any full or pro model. Reasoning models are especially wasteful
here — internal chain-of-thought tokens inflate the budget with no benefit.

**Token budget:** 200 (non-reasoning) / 800 (reasoning).

---

### 2. DM Query

**What it does:** answers a player's out-of-character question (e.g. "What
are my character's known spells?") using the current context. No mechanics,
no state mutations, no narrative advancement. Output is a JSON blob with
an `answer` field.

**Cognitive demand:** low to moderate. Needs to read context and produce a
coherent answer, but never reasons about rules or outcomes.

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

**Acceptable:** gpt-4.1-mini, gpt-5-mini

**Avoid:** full and pro models. The answers are short factual lookups against
provided context. Throwing a reasoning model at "What's in my inventory?"
is pure waste.

**Token budget:** 300 (non-reasoning) / 1600 (reasoning).

---

### 2b. Sequencer

**What it does:** detects compound player inputs that describe multiple
sequential actions ("I rest, then head to the village") and splits them
into an ordered queue. Runs before Intent when `action_queue` is enabled.

**Cognitive demand:** low. Classification + extraction of temporal
sequences. Must distinguish simultaneous actions ("sneak and pick the
lock") from sequential ones ("rest, then travel").

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

**Acceptable:** gpt-4.1-mini for edge cases with subtle temporal cues.

**Avoid:** full and pro models. Task is simple classification.

**Token budget:** 200 (non-reasoning). Output is a small JSON array.

---

### 3. Intent

**What it does:** pure intention extraction. Given the player input and
current micro-contexts, determines the player's intention, which contexts
are affected, whether mechanics are needed, and whether the action is
macro-significant. Does **not** interpret rules or dispatch domain logic —
that is handled by InterpretationDispatcher. Output is a small structured
JSON blob.

**Cognitive demand:** low to moderate. Must understand multi-context actions
like "I jump into the sacred lake to flee my attackers", but the output is
still extractive classification.

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

**Acceptable:** gpt-4.1-mini, gpt-5-mini. If multi-context actions are
frequently misclassified with nano, stepping up to mini is worthwhile.

**Avoid:** full and pro models. The task is fundamentally extractive, not
generative.

**Token budget:** 400 (non-reasoning) / 1600 (reasoning).

---

### 4. InterpretationDispatcher

**What it does:** dispatches domain-specific interpretation in parallel.
One interpreter fires per affected context (e.g., `combat_interpreter`,
`traversal_interpreter`, `social_interpreter`). Each interprets the player's
intent within its domain rules and produces a structured domain brief. Which
contexts receive prompts is configurable via `interpreter_scope` toggle:
`"always_all"` sends every context, `"classify_driven"` only sends those
flagged by Classify.

**Cognitive demand:** moderate. Each interpreter must understand its
domain's rules well enough to produce accurate structured output, but the
scope is narrower than a full ruling.

**Recommended:** gpt-4o-mini, gpt-4.1-mini, gpt-5-nano

Mini models are the sweet spot — smart enough for domain-specific rule
interpretation, cheap enough to run several in parallel.

**Acceptable:** gpt-5-mini, o4-mini

Stepping up to reasoning minis is worthwhile if interpreters frequently
misjudge rule interactions within their domain.

**Avoid:**

- Full and pro models: you may run 2-6 interpreters per turn; full-tier
pricing multiplied by dispatcher count gets expensive fast.
- gpt-3.5-turbo: struggles with structured domain output.

**Token budget:** 400 (non-reasoning) / 1600 (reasoning) per dispatcher.
Total cost scales with the number of dispatched domains.

---

### 5. CapabilityGuardrail

**What it does:** validates that the player's character can actually
perform the intended action — checks spells known, feat prerequisites,
item possession, class features, etc. Runs in parallel with
MechanicalEvaluation. Configurable via `guardrail_mode`: `"code"` uses
app-level validation, `"ai"` uses an AI call. **Only the AI mode requires
model selection.**

**Cognitive demand:** moderate. Must cross-reference the character sheet
with the intended action and identify capability mismatches.

**Recommended:** gpt-4o-mini, gpt-4.1-mini, gpt-5-nano

The task is a structured lookup against the character sheet — mini models
handle it well.

**Acceptable:** gpt-5-mini, o4-mini

**Avoid:**

- Full and pro models: overpowered for a validation check.
- Nano models (non-reasoning): may miss subtle prerequisites (e.g.,
caster level requirements, feat chains).

**Token budget:** 400 (non-reasoning) / 1600 (reasoning).

---

### 6. MechanicalEvaluation

**What it does:** the most rules-heavy step. Given the player's intent,
domain interpretations, and the relevant Pathfinder rules, determines what
dice rolls are needed, what the DCs are, and what NPC actions occur. This
step can request player rolls (pausing the pipeline) or resolve NPC rolls
internally.

**Cognitive demand:** high. The model must accurately interpret Pathfinder 1e
rules (attack of opportunity triggers, grapple flowcharts, skill check DCs,
spell effects), compose them correctly with the current context, and produce
structured JSON. Mistakes here cause incorrect gameplay.

**Recommended:** o3-mini, o4-mini, gpt-5-mini

Reasoning capability for rules interpretation at moderate cost. The
chain-of-thought helps the model "think through" the rules rather than
pattern-match. gpt-5-mini brings GPT-5-class reasoning at $0.25/$2.00.

**Acceptable:** gpt-5, o3, gpt-4.1

gpt-4.1 is the best non-reasoning option if you want temperature control,
but it lacks chain-of-thought and can miss edge cases in complex rule
interactions.

**Avoid:**

- Nano models: they will frequently misapply rules, miss AoO triggers,
or produce malformed JSON on complex multi-check scenarios.
- Pro models: correct but absurdly expensive.
- gpt-3.5-turbo: cannot reliably handle Pathfinder's rule complexity.

**Token budget:** 500 (non-reasoning) / 2000 (reasoning).

---

### 6b. RollQualifier

**What it does:** runs after each MechanicalEvaluation domain iteration that
produces player rolls. Evaluates the character's situational state to
determine: (a) situational modifiers like flanking, high ground, cover, or
circumstance bonuses, and (b) Take 10 / Take 20 eligibility based on
threat level, time pressure, and failure consequences.

**Cognitive demand:** low to moderate. The model reads broader context
(configurable scope) and makes a situational judgment. No complex rules
calculation — just assessing "is the character under duress?"

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

Fast and cheap. The task is straightforward situational assessment, not
rules adjudication. A nano model with sufficient context window handles
this reliably.

**Acceptable:** gpt-4.1-mini, o3-mini

If you want higher reliability on edge cases (e.g., "is the nearby NPC
hostile enough to count as a threat for Take 10?"), a mini-class model
provides better judgment.

**Avoid:**

- Pro models: massive overkill for a simple assessment.
- Reasoning models are unnecessary here unless context is very large (use
  `roll_qualifier_scope: "all"` with a larger model).

**Token budget:** 400.

---

### 7. Ruling

**What it does:** post-roll arbitration. Given roll results (player and NPC),
the mechanical evaluation, and the player's character sheet, determines the
final mechanical outcome. Did the attack hit? How much damage? Did the
grapple succeed? What conditions apply? Output is structured JSON with
mutations (HP changes, conditions, position updates).

**Cognitive demand:** high. The model must correctly apply modifiers,
compare against DCs/ACs, handle critical hit confirmation, damage reduction,
spell resistance, etc. Errors here directly produce wrong HP values,
missed conditions, or ignored saves.

**Recommended:** o3-mini, o4-mini, gpt-5-mini

Chain-of-thought helps the model work through arithmetic and conditional
logic step-by-step instead of jumping to (frequently wrong) conclusions.

**Acceptable:** gpt-5, o3, gpt-4.1

**Avoid:**

- Nano models: arithmetic errors are common, especially with multiple
stacking modifiers.
- Pro models: not worth the cost.
- gpt-3.5-turbo: struggles with multi-step arithmetic.

**Token budget:** 600 (non-reasoning) / 2400 (reasoning).

---

### 7b. TimeKeeper

**What it does:** estimates in-game time for any player action and orchestrates
time-related utilities. Uses code-first estimation for journeys (deterministic
distance/speed/terrain math), combat (6 seconds), rest (8 hours), and Take 20
(~40 minutes). Falls back to a cheap AI call for freeform actions (wait, craft,
freeform travel). Output: `{ "hours_elapsed": N, "reasoning": "..." }`.

Also consults Harbinger (encounter utility) for interrupt checks and calls
GameClock (clock utility) for time advancement. Both utilities are code-only.

**AI is only called for freeform actions** — most common actions (journey to
a known destination, combat, rest) are resolved entirely in code.

**Cognitive demand:** very low (when AI is needed). Simple estimation of a
single number based on Pathfinder 1e time conventions.

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

Nano models handle this perfectly. The output is 2-3 fields and the task is
straightforward time estimation.

**Acceptable:** gpt-4.1-mini, gpt-5-mini

**Avoid:** full, reasoning, and pro models. This is not a task that benefits
from chain-of-thought — it's a simple lookup.

**Token budget:** 300 (non-reasoning) / 1200 (reasoning).

---

### 8. Evaluate (code-only)

**What it does:** a code-only synthesis and routing step. Takes the ruling
outcome, generates a `narrative_seed` and `context_update_directives`, and
dispatches the output phase (Narrate + ContextUpdate). **No AI call — no
model selection needed.** Included here for pipeline completeness.

The output phase mode is controlled by the `narration_mode` toggle:
`"parallel"` runs Narrate and ContextUpdate concurrently, `"subjugated"`
runs ContextUpdate first, then Narrate.

---

### 9. Narrate

**What it does:** the player-facing creative step. Takes the mechanical
outcome (or lack thereof, for non-mechanical actions) and produces the
DM's narrative response. This is what the player reads. Quality here is
the single biggest driver of player experience.

**Cognitive demand:** moderate (rules-wise) but high (creatively). The model
must weave mechanical results into compelling prose, maintain tone
consistency, respect the adventure's setting, and optionally handle
"directed play" pacing. It does not need to reason about rules — just
tell a good story.

**Recommended:** gpt-4.1, gpt-4o, gpt-5

Non-reasoning models are *preferred* here because they support
`temperature` tuning, which directly controls narrative creativity. A
temperature of 0.8-1.0 produces varied, engaging prose; reasoning models
are locked to temperature 1.0 and tend toward more clinical output.

gpt-4.1 ($2.00/$8.00) is the current best non-reasoning model and
produces excellent prose. gpt-4o ($2.50/$10.00) is a close alternative.
gpt-5 ($1.25/$10.00) has reasoning capability and writes well but lacks
temperature control.

**Acceptable:** gpt-4.1-mini, gpt-5-mini

Mini models produce decent narrative at 5-10x lower cost. If operating on
a tight budget, gpt-4.1-mini is a reasonable trade-off — prose quality drops
noticeably but remains coherent.

**Avoid:**

- Nano models: the narrative quality cliff is steep. gpt-4.1-nano produces
flat, repetitive, and sometimes incoherent prose. Players will notice.
- o-series reasoning models (o3, o4-mini, etc.): they "think" about what
to write instead of just writing it, which consumes reasoning tokens
without improving (and sometimes degrading) narrative quality. The
internal chain-of-thought eats into your token budget for output that
the player never sees.
- gpt-3.5-turbo: noticeably worse prose, frequent tone breaks.
- Pro models: gpt-5-pro writes beautifully but at $15/$120, a single
narrative response costs more than the rest of the pipeline combined.

**Token budget:** 800 (non-reasoning) / 3200 (reasoning). This is the
largest budget because narrative output is the longest.

---

### 10. Micro Context Update

**What it does:** updates the micro-context JSONB fields on the Adventure
(traversal, combat, social, exploration, rest, inventory). Only *relevant*
contexts are included in the prompt — those flagged as affected by the
Intent step plus any that already have data. Receives the factual outcome
summary and mutations (not the narrative text), decides what changed, and
outputs the updated context state as structured JSON. Runs in parallel
with Narrate (in parallel narration mode) or before Narrate (in
subjugated mode).

**Cognitive demand:** moderate. Must accurately reflect mechanical changes
(enemy died, player moved, social attitude shifted) in a structured format.
Judgement is needed to decide what's relevant — not everything in the
narrative belongs in context.

**Recommended:** gpt-4.1-mini, gpt-4o-mini, gpt-5-nano

Mini models are the sweet spot. The task is structured-output-heavy (JSON)
with moderate judgment. gpt-4o-mini at $0.15/$0.60 is particularly
cost-effective. gpt-5-nano has reasoning capability at even lower cost
($0.05/$0.40) and may produce more consistent JSON.

**Acceptable:** gpt-4.1-nano, gpt-4.1, gpt-5-mini

gpt-4.1-nano can handle simpler updates but may miss subtle context changes
in complex multi-context scenarios. gpt-4.1 is overkill but reliable.

**Avoid:**

- Full/pro reasoning models: the internal chain-of-thought on a context
update is wasted compute.
- gpt-3.5-turbo: inconsistent JSON structure.

**Token budget:** 800 (non-reasoning) / 3200 (reasoning).

---

### 11. Macro Narrative Update

**What it does:** conditionally updates the adventure's `story_summary`
field. Only fires when the intent step flagged the action as
`macro_significant`. Reads the current narrative and summary, and decides
whether and how to update the high-level story arc.

**Cognitive demand:** moderate. The model needs good judgment to decide
what rises to the level of "story-significant" — a goblin dying isn't, but
the king being assassinated is. The output is a short text summary update.

**Recommended:** gpt-4.1-mini, gpt-4o-mini, gpt-5-nano

Same rationale as micro context update. This step fires less frequently
(only on macro-significant actions), so even if you pick a slightly
pricier model, the amortized cost per turn is low.

**Acceptable:** gpt-4.1, gpt-5-mini

Stepping up to a full model can improve the quality of the summary text,
which accumulates over the adventure and feeds back into future prompts.
If the story summary is a core part of your experience, spending more
here has downstream benefits.

**Avoid:**

- Nano models: they tend to either over-summarize (including everything)
or under-summarize (missing the point), degrading the macro context
over time.
- Pro models: not justified for a one-paragraph text update.

**Token budget:** 500 (non-reasoning) / 2000 (reasoning).

---

### 12. Chronicler

**What it does:** summarizes the pipeline outcome for logging and the
time-span resolver. Produces a concise scene summary and optional story
beat. Fires after the output phase.

**Cognitive demand:** low to moderate. Summarization of known outcomes.

**Recommended:** gpt-4o-mini, gpt-4.1-mini, gpt-5-nano

**Acceptable:** gpt-4.1-nano

**Avoid:** full and pro models.

**Token budget:** 400 (non-reasoning) / 1600 (reasoning).

---

### Edge Pipeline (alternative mode)

**What it does:** a single monolithic AI call that handles the entire
pipeline — sanitization, intent, capability checks, mechanics (with
internally simulated dice rolls), mutations, narration, and context updates.
Activated via `pipeline_mode: "edge"` in DmConfig.

**Cognitive demand:** very high. The model must juggle every responsibility
in one pass. Quality depends heavily on the model's ability to follow a
complex, multi-section prompt.

**Recommended:** gpt-5, o3, gpt-4.1

Full-tier models are the minimum for acceptable output. The prompt is long
and the model must produce multiple structured sections plus narrative.
gpt-4.1 at $2.00/$8.00 is the best non-reasoning option.

**Acceptable:** gpt-5-mini, o3-mini

Mini reasoning models can handle it but may miss nuance in narration or
produce abbreviated context updates.

**Avoid:**

- Nano models: will fail on the multi-section structured output.
- Pro models: the cost of a single edge call at pro pricing is
prohibitive for real-time use.

**Token budget:** 2000 (non-reasoning) / 8000 (reasoning). This is the
largest budget in the system because the model produces all outputs in
one response.

---

## Cost Profiles

The following estimates assume one player turn = sanitize + classify
(parallel) + intent + 2 interpretation dispatchers (average) +
capability guardrail + mechanical evaluation (parallel with guardrail) +
roll qualifier (when rolls exist, ~50% of turns) +
ruling + narrate + micro context update + macro narrative update (~20%
of the time). Evaluate is code-only and has no AI cost.

### Budget build (minimize cost)


| Step             | Model        | Est. cost/turn   |
| ---------------- | ------------ | ---------------- |
| Sanitize         | gpt-4.1-nano | ~$0.0001         |
| Classify         | gpt-4.1-nano | ~$0.0001         |
| DM Query         | gpt-4.1-nano | ~$0.0001         |
| Intent           | gpt-4.1-nano | ~$0.0002         |
| Dispatchers (×2) | gpt-4o-mini  | ~$0.0004         |
| Cap. Guardrail   | gpt-4.1-nano | ~$0.0001         |
| Mech. Eval       | gpt-4o-mini  | ~$0.0005         |
| Roll Qualifier   | gpt-4.1-nano | ~$0.0001         |
| Ruling           | gpt-4o-mini  | ~$0.0005         |
| TimeKeeper       | gpt-4.1-nano | ~$0.0001         |
| Narrate          | gpt-4.1-mini | ~$0.001          |
| Micro Ctx        | gpt-4.1-nano | ~$0.0002         |
| Macro Narr       | gpt-4.1-nano | ~$0.0001         |
| **Total**        |              | **~$0.004/turn** |


Quality trade-off: more AI calls than before, but cheap steps stay
cheap. Rulings may occasionally misfire on complex interactions;
narrative will be competent but not immersive.

### Balanced build (recommended starting point)


| Step             | Model       | Est. cost/turn   |
| ---------------- | ----------- | ---------------- |
| Sanitize         | gpt-5-nano  | ~$0.0001         |
| Classify         | gpt-5-nano  | ~$0.0001         |
| DM Query         | gpt-5-nano  | ~$0.0001         |
| Intent           | gpt-5-nano  | ~$0.0002         |
| Dispatchers (×2) | gpt-4o-mini | ~$0.001          |
| Cap. Guardrail   | gpt-4o-mini | ~$0.0003         |
| Mech. Eval       | o4-mini     | ~$0.005          |
| Roll Qualifier   | gpt-4o-mini | ~$0.0003         |
| Ruling           | o4-mini     | ~$0.005          |
| TimeKeeper       | gpt-5-nano  | ~$0.0001         |
| Narrate          | gpt-4.1     | ~$0.008          |
| Micro Ctx        | gpt-4o-mini | ~$0.0005         |
| Macro Narr       | gpt-4o-mini | ~$0.0002         |
| **Total**        |             | **~$0.02/turn**  |


Quality trade-off: strong rules accuracy from reasoning models, good
narrative from a full-tier model. The bulk of cost comes from narration
and the two mechanical steps.

### Premium build (maximize quality)


| Step             | Model        | Est. cost/turn   |
| ---------------- | ------------ | ---------------- |
| Sanitize         | gpt-4o-mini  | ~$0.0002         |
| Classify         | gpt-4o-mini  | ~$0.0002         |
| DM Query         | gpt-4.1-mini | ~$0.0005         |
| Intent           | gpt-4.1-mini | ~$0.001          |
| Dispatchers (×2) | gpt-4.1-mini | ~$0.002          |
| Cap. Guardrail   | gpt-4.1-mini | ~$0.0005         |
| Mech. Eval       | o3           | ~$0.01           |
| Roll Qualifier   | gpt-4.1-mini | ~$0.0005         |
| Ruling           | o3           | ~$0.01           |
| TimeKeeper       | gpt-4o-mini  | ~$0.0002         |
| Narrate          | gpt-5        | ~$0.01           |
| Micro Ctx        | gpt-4.1-mini | ~$0.001          |
| Macro Narr       | gpt-4.1      | ~$0.003          |
| **Total**        |              | **~$0.04/turn**  |


Quality trade-off: best available accuracy and prose. The additional
dispatcher and guardrail steps add marginal cost but meaningfully improve
rule accuracy and capability validation.

### Edge build (single-call alternative)


| Step          | Model   | Est. cost/turn   |
| ------------- | ------- | ---------------- |
| Edge Pipeline | gpt-4.1 | ~$0.015          |
| **Total**     |         | **~$0.015/turn** |


Quality trade-off: simplest deployment, no inter-step latency, but less
fine-grained control over model selection per concern. Quality depends
entirely on the chosen model's ability to handle the compound prompt.

---

## Key Considerations

### Reasoning models need higher token budgets

Reasoning models (o-series, gpt-5.x) consume tokens internally for
chain-of-thought before producing visible output. Our default budgets are
roughly 4x higher for reasoning models. If you see `finish_reason: length`
errors after switching a step to a reasoning model, the first thing to
check is the token budget.

### Temperature is only available on non-reasoning models

Models marked with `supports_temperature: false` in `openai_models.json`
ignore the temperature setting. This matters most for the Narrate step,
where temperature directly controls creative variance. If you use a
reasoning model for narration, you lose this control.

### Interpretation dispatchers scale with affected contexts

InterpretationDispatcher fires one AI call per affected domain context.
A multi-context action ("I leap into the sacred lake to escape my
attackers") may produce 2-3 parallel dispatcher calls. Factor this into
cost estimates — the more contexts touched, the higher the per-turn
dispatcher cost.

### Context updates compound over time

Micro and macro context updates feed into every future prompt. A cheap
model that produces slightly degraded context will cause downstream
quality loss across all subsequent turns. This is a subtle cost that
doesn't show up in per-turn pricing but can degrade the adventure over
a long session. When in doubt, spend slightly more here.

### Parallel steps add latency savings but not cost savings

Sanitize + Classify, CapabilityGuardrail + MechanicalEvaluation, and
Narrate + ContextUpdate (in parallel mode) run concurrently. Wall-clock
time improves, but you still pay for every call. When budgeting, count
all parallel steps at full price.

### Edge pipeline vs. standard pipeline trade-off

Edge mode collapses all AI calls into one, eliminating inter-step
latency and simplifying deployment. However, you lose per-step model
selection, per-step token budgets, and fine-grained logging. It's best
suited for low-traffic deployments or as a fast fallback when latency
is more important than accuracy.

### Fine-tuning potential

Steps that produce structured JSON with consistent schemas (sanitize,
classify, intent, interpretation dispatchers, mechanical evaluation,
ruling, context updates) are strong candidates for fine-tuning on a
cheaper base model. Over time, you can collect AiLog data, curate
high-quality examples, and fine-tune gpt-4o-mini or gpt-4.1-nano to
match the accuracy of larger models at a fraction of the cost. Narration
is harder to fine-tune because quality is subjective, but it's possible
with a well-curated dataset.

---

## Non-OpenAI Models

The pipeline currently targets the OpenAI chat completions API exclusively.
This section surveys models from other providers, evaluates their suitability
per pipeline step, and outlines what an integration would require.

### Anthropic (Claude)

**Models:** Claude 4 Opus, Claude 4 Sonnet, Claude 3.5 Haiku


| Model            | Input (per 1M) | Output (per 1M) | Context | Notes                                  |
| ---------------- | -------------- | --------------- | ------- | -------------------------------------- |
| Claude 4 Opus    | ~$15.00        | ~$75.00         | 200K    | Top-tier reasoning and prose           |
| Claude 4 Sonnet  | ~$3.00         | ~$15.00         | 200K    | Strong balance of cost and quality     |
| Claude 3.5 Haiku | ~$0.80         | ~$4.00          | 200K    | Fast, cheap, good at structured output |


**Strengths:**

- Excellent at following complex, multi-constraint instructions — directly
relevant to the MechanicalEvaluation and Ruling steps where Pathfinder
rules must be interpreted precisely.
- Claude models tend to produce high-quality, stylistically consistent
prose, making them strong Narrate candidates.
- Very large context windows (200K tokens) mean micro/macro context can be
passed in full without truncation concerns.
- Strong JSON mode support via tool use / structured output features.

**Weaknesses:**

- No native "reasoning model" toggle like o-series. Claude thinks inline,
which is generally fine but means you can't force extended deliberation
on a hard ruling the way o3's chain-of-thought does.
- API shape differs from OpenAI: different auth, message format, and
streaming protocol. Requires a second client implementation.
- Rate limits and availability can be tighter than OpenAI for high-volume
use.

**Step fit:**


| Step             | Fit       | Model          | Why                                    |
| ---------------- | --------- | -------------- | -------------------------------------- |
| Sanitize         | Overkill  | Haiku          | Works but OpenAI nano is cheaper       |
| Classify         | Overkill  | Haiku          | Works but OpenAI nano is cheaper       |
| DM Query         | Good      | Haiku          | Comparable to gpt-4o-mini              |
| Intent           | Good      | Haiku          | Reliable classification                |
| Dispatchers      | Good      | Haiku          | Clean domain interpretation            |
| Cap. Guardrail   | Good      | Haiku          | Strong instruction-following           |
| Mech. Eval       | Excellent | Sonnet         | Instruction-following shines here      |
| Ruling           | Excellent | Sonnet         | Careful with modifiers and arithmetic  |
| Narrate          | Excellent | Sonnet / Opus  | Best-in-class prose at the Sonnet tier |
| Micro Ctx        | Good      | Haiku          | Clean JSON output                      |
| Macro Narr       | Good      | Haiku / Sonnet | Good judgment on significance          |


**Desirability: High.** Claude Sonnet for mech. eval/ruling/narrate paired
with OpenAI nano for cheap steps would be a strong hybrid setup. Sonnet's
instruction-following is arguably better than o3-mini for rule-heavy steps,
and its prose rivals gpt-4.1 at a comparable price point.

---

### Google (Gemini)

**Models:** Gemini 2.5 Pro, Gemini 2.5 Flash, Gemini 2.0 Flash


| Model            | Input (per 1M) | Output (per 1M) | Context | Notes                               |
| ---------------- | -------------- | --------------- | ------- | ----------------------------------- |
| Gemini 2.5 Pro   | ~$1.25         | ~$10.00         | 1M      | "Thinking" mode with reasoning      |
| Gemini 2.5 Flash | ~$0.15         | ~$0.60          | 1M      | Fast, very cheap, thinking optional |
| Gemini 2.0 Flash | ~$0.10         | ~$0.40          | 1M      | Predecessor, still available        |


**Strengths:**

- Extremely large context windows (1M tokens). Could theoretically hold
the entire adventure history in context, eliminating summarization.
- Gemini 2.5 Flash is remarkably cheap and fast — competitive with
gpt-4o-mini on price and often faster.
- Gemini 2.5 Pro's "thinking" mode provides chain-of-thought reasoning
similar to o-series models.
- Good at structured output / JSON generation.

**Weaknesses:**

- JSON reliability can be inconsistent compared to OpenAI, particularly
with deeply nested structures. May require more aggressive schema
validation on our side.
- Prose quality, while improved in 2.5, still tends toward a more
"informational" tone compared to Claude or GPT-4.1. Narration may
feel slightly clinical.
- Gemini's safety filters can be aggressive in fantasy violence contexts
(combat descriptions, creature attacks), potentially triggering false
refusals that would break the pipeline.
- API is REST-based but structurally different from OpenAI (different
message roles, different tool call format, different streaming).

**Step fit:**


| Step             | Fit        | Model     | Why                                 |
| ---------------- | ---------- | --------- | ----------------------------------- |
| Sanitize         | Excellent  | 2.0 Flash | Extremely cheap classification      |
| Classify         | Excellent  | 2.0 Flash | Extremely cheap classification      |
| DM Query         | Good       | 2.5 Flash | Fast Q&A                            |
| Intent           | Good       | 2.5 Flash | Cheap and capable enough            |
| Dispatchers      | Good       | 2.5 Flash | Cheap domain interpretation         |
| Cap. Guardrail   | Good       | 2.5 Flash | Fast validation                     |
| Mech. Eval       | Good       | 2.5 Pro   | Thinking mode helps with rules      |
| Ruling           | Good       | 2.5 Pro   | Thinking mode helps with arithmetic |
| Narrate          | Mediocre   | 2.5 Pro   | Functional but less immersive prose |
| Micro Ctx        | Good       | 2.5 Flash | Cheap structured output             |
| Macro Narr       | Acceptable | 2.5 Flash | Tends to over-include in summaries  |


**Desirability: Medium.** The cost advantage is real, especially on the
cheap steps where Gemini Flash undercuts even OpenAI nano. However, the
safety filter risk in a fantasy RPG context is a significant operational
concern — a blocked response mid-combat would break the player experience.
Worth investigating with thorough testing of combat/violence scenarios
before committing.

---

### Meta (Llama)

**Models:** Llama 4 Maverick, Llama 4 Scout, Llama 3.3 70B, Llama 3.1 405B

These are open-weight models. Pricing depends on the hosting provider
(Together AI, Fireworks, Groq, AWS Bedrock, self-hosted).


| Model            | Typical hosted cost (per 1M in/out) | Parameters | Notes                      |
| ---------------- | ----------------------------------- | ---------- | -------------------------- |
| Llama 4 Maverick | ~$0.20 / ~$0.60                     | MoE 400B+  | Latest, mixture-of-experts |
| Llama 4 Scout    | ~$0.10 / ~$0.30                     | MoE ~100B  | Smaller, faster MoE        |
| Llama 3.3 70B    | ~$0.10 / ~$0.30                     | 70B        | Solid workhorse            |
| Llama 3.1 405B   | ~$0.80 / ~$2.40                     | 405B       | Largest dense Llama        |


**Strengths:**

- Open weights mean self-hosting is possible, eliminating per-token cost
entirely (only infrastructure cost). Attractive for high-volume use.
- Hosted providers like Groq and Fireworks offer extremely low latency
(sometimes faster than OpenAI).
- Llama 4 Maverick is competitive with GPT-4o on many benchmarks.
- Fine-tuning is unrestricted and much cheaper than OpenAI fine-tuning.
Particularly relevant for steps with consistent schemas (sanitize,
classify, intent, mechanical evaluation, ruling).
- No content policy restrictions — the model won't refuse fantasy violence.

**Weaknesses:**

- Instruction-following on complex multi-constraint prompts (mechanical
evaluation, ruling) is noticeably weaker than GPT-4.1 or Claude Sonnet, especially
for Pathfinder edge cases the model has seen less of in training.
- JSON output reliability is lower. Llama models more frequently produce
malformed JSON, hallucinate extra fields, or omit required ones. Needs
robust parsing with fallbacks.
- No built-in "reasoning mode." Extended thinking must be prompted manually
(e.g., "think step by step"), which is less reliable and harder to
budget tokens for.
- Prose quality varies significantly. Llama 3.3 70B can write decent
narrative but with less stylistic range than GPT-4.1 or Sonnet.
Maverick is better but still a step below.

**Step fit:**


| Step             | Fit        | Model              | Why                                             |
| ---------------- | ---------- | ------------------ | ----------------------------------------------- |
| Sanitize         | Good       | Scout / 3.3 70B    | Simple enough task, very cheap                  |
| Classify         | Good       | Scout / 3.3 70B    | Simple enough task, very cheap                  |
| DM Query         | Good       | Scout / 3.3 70B    | Straightforward lookups                         |
| Intent           | Acceptable | Maverick / 3.3 70B | May need prompt tuning for multi-context        |
| Dispatchers      | Acceptable | 3.3 70B            | Needs prompt tuning for domain accuracy         |
| Cap. Guardrail   | Acceptable | 3.3 70B            | Validation checks, but may miss prerequisites   |
| Mech. Eval       | Weak       | Maverick / 405B    | Rule misapplication risk without reasoning mode |
| Ruling           | Weak       | Maverick / 405B    | Arithmetic and modifier stacking issues         |
| Narrate          | Acceptable | Maverick           | Functional prose, lacks flair                   |
| Micro Ctx        | Acceptable | 3.3 70B            | JSON output needs validation layer              |
| Macro Narr       | Acceptable | 3.3 70B            | Tends toward verbose summaries                  |


**Desirability: Medium-Low for hosted, Medium-High for self-hosted with
fine-tuning.** Out of the box, Llama models aren't competitive with OpenAI
or Claude on the critical steps (mech. eval, ruling, narrate). However, if
you invest in fine-tuning — using AiLog data from a higher-quality model
as training examples — a fine-tuned Llama 3.3 70B could potentially match
gpt-4o-mini accuracy on structured steps at near-zero marginal cost. This
is the strongest case for Llama: a long-term cost optimization play.

---

### Mistral

**Models:** Mistral Large, Mistral Medium, Mistral Small, Codestral


| Model         | Input (per 1M) | Output (per 1M) | Notes                        |
| ------------- | -------------- | --------------- | ---------------------------- |
| Mistral Large | ~$2.00         | ~$6.00          | Flagship, strong reasoning   |
| Mistral Small | ~$0.10         | ~$0.30          | Fast, cheap                  |
| Codestral     | ~$0.30         | ~$0.90          | Code-optimized, good at JSON |


**Strengths:**

- Mistral Large is strong at structured output and instruction-following,
competitive with GPT-4o on many tasks.
- Mistral Small is very cheap and fast — a viable alternative to
gpt-4o-mini for classification steps.
- Codestral, while code-focused, tends to produce very clean JSON, which
is useful for structured pipeline steps.
- European provider, which may matter for data residency requirements.
- Function calling / tool use support is well-implemented.

**Weaknesses:**

- Smaller training data footprint means less exposure to Pathfinder/d20
rules compared to OpenAI or Anthropic models. Mechanical evaluation and
ruling accuracy may suffer on niche rules (grapple flowchart, combat
maneuver bonuses).
- Prose quality on Mistral Large is functional but tends to be more
utilitarian than GPT-4.1 or Claude. Narration may feel workmanlike.
- The model lineup changes frequently and older models are deprecated
aggressively, requiring more maintenance.
- Smaller community and fewer third-party tools/libraries.

**Step fit:**


| Step             | Fit        | Model             | Why                                      |
| ---------------- | ---------- | ----------------- | ---------------------------------------- |
| Sanitize         | Good       | Small             | Cheap classification                     |
| Classify         | Good       | Small             | Cheap classification                     |
| DM Query         | Good       | Small             | Simple Q&A                               |
| Intent           | Good       | Small             | Pattern recognition                      |
| Dispatchers      | Acceptable | Small / Large     | Small for simple domains, Large for edge |
| Cap. Guardrail   | Acceptable | Small             | Basic validation                         |
| Mech. Eval       | Acceptable | Large             | Functional but less Pathfinder knowledge |
| Ruling           | Acceptable | Large             | Decent arithmetic, some edge case misses |
| Narrate          | Mediocre   | Large             | Prose is serviceable but dry             |
| Micro Ctx        | Good       | Codestral / Small | Clean JSON from Codestral                |
| Macro Narr       | Acceptable | Small             | Reasonable judgment                      |


**Desirability: Low-Medium.** Mistral doesn't clearly outperform OpenAI on
any step, and the smaller model ecosystem means fewer options when
something doesn't work. The best use case would be Mistral Small as an
alternative to gpt-4o-mini on cheap steps, or Codestral for steps that
are pure JSON transformation.

---

### DeepSeek

**Models:** DeepSeek-R1, DeepSeek-V3


| Model       | Input (per 1M) | Output (per 1M) | Notes                            |
| ----------- | -------------- | --------------- | -------------------------------- |
| DeepSeek-R1 | ~$0.55         | ~$2.19          | Chain-of-thought reasoning model |
| DeepSeek-V3 | ~$0.27         | ~$1.10          | General-purpose, very capable    |


**Strengths:**

- DeepSeek-R1 is a dedicated reasoning model at a fraction of o3's price.
For mechanical evaluation and ruling steps, the cost savings compared to o3-mini
($1.10/$4.40) are significant.
- DeepSeek-V3 benchmarks competitively with GPT-4o on many tasks at
roughly 1/10 the price.
- Both models handle structured JSON output well.
- Open-weight variants are available for self-hosting.

**Weaknesses:**

- Availability and latency can be inconsistent. DeepSeek's API has
experienced significant downtime and rate limiting during high-demand
periods.
- R1's chain-of-thought output format differs from OpenAI's — the
reasoning is emitted as visible content, not hidden. Parsing requires
stripping the thinking block before processing the actual response.
- Less battle-tested in production English-language applications. Some
edge cases in English phrasing and Pathfinder-specific terminology
may trip up the model more than OpenAI equivalents.
- Data residency considerations (China-based provider) may be relevant
for some deployments.

**Step fit:**


| Step             | Fit        | Model | Why                                         |
| ---------------- | ---------- | ----- | ------------------------------------------- |
| Sanitize         | Good       | V3    | Cheap, fast classification                  |
| Classify         | Good       | V3    | Cheap, fast classification                  |
| DM Query         | Good       | V3    | Straightforward                             |
| Intent           | Good       | V3    | Capable classification                      |
| Dispatchers      | Good       | V3    | Decent domain interpretation                |
| Cap. Guardrail   | Good       | V3    | Capable validation                          |
| Mech. Eval       | Good       | R1    | Reasoning at great price                    |
| Ruling           | Good       | R1    | Chain-of-thought helps arithmetic           |
| Narrate          | Acceptable | V3    | Functional but English prose can feel stiff |
| Micro Ctx        | Good       | V3    | Clean JSON output                           |
| Macro Narr       | Acceptable | V3    | Adequate judgment                           |


**Desirability: Medium-High (with caveats).** DeepSeek offers the best
price-to-reasoning-quality ratio available. R1 on mech. eval/ruling is
a compelling alternative to o3-mini at half the cost. The main risks are
operational (uptime, latency) rather than capability. If reliability
concerns are acceptable, DeepSeek is a strong secondary provider.

---

### Implementation Requirements for Multi-Provider Support

The current architecture routes all calls through `DungeonMaster::AiClient`,
which wraps the OpenAI Ruby client. Supporting non-OpenAI models would
require:

1. **Provider abstraction layer.** Extract an `AiProvider` interface from
  `AiClient` with a standard `#chat(messages:, model:, max_tokens:, ...)`
   contract. Each provider gets its own implementation:
  - `AiProviders::OpenAi` (current logic)
  - `AiProviders::Anthropic`
  - `AiProviders::Google`
  - `AiProviders::OpenAiCompatible` (covers DeepSeek, Mistral, Llama
  hosted providers that expose an OpenAI-compatible API)
2. **Model catalog expansion.** Extend `openai_models.json` into a
  `models.json` (or provider-specific files) that includes a `provider`
   field. `OpenaiModelCatalog` becomes `ModelCatalog` and resolves which
   provider class to instantiate.
3. **Per-step provider routing.** The existing `DmConfig#model_for(step)`
  already returns a model ID per step. The pipeline would resolve
   `provider_for(model_id)` to get the right client, then call
   `client.chat(...)`. This is the smallest change — the pipeline doesn't
   care what provider is behind the model.
4. **Response normalization.** Each provider returns different response
  structures. The provider abstraction must normalize to a common format:
   `{ content:, finish_reason:, usage: { input_tokens:, output_tokens: } }`.
5. **Error normalization.** Map provider-specific errors (Anthropic's
  `overloaded_error`, Google's `RESOURCE_EXHAUSTED`, etc.) to our
   existing `AiError` / `TokenBudgetExceededError` hierarchy.
6. **Credential management.** Each provider needs its own API key. Extend
  `DmConfig` or use Rails credentials to store per-provider keys.
7. **Reasoning output parsing.** DeepSeek-R1 and similar models emit
  chain-of-thought as visible content (wrapped in `<think>` tags). The
   provider layer should strip this before returning content, but preserve
   it in the `reasoning` field for logging.

**Estimated effort:** The OpenAI-compatible providers (DeepSeek, Mistral,
hosted Llama) are the easiest — often just a base URL change in the
existing client. Anthropic and Google require full client implementations
due to different API shapes. A phased approach is recommended:

- **Phase 1:** Support OpenAI-compatible providers via a `base_url`
override in `AiClient`. Unlocks DeepSeek, Mistral, Fireworks-hosted
Llama with minimal code changes.
- **Phase 2:** Add Anthropic provider (highest value non-OpenAI option).
- **Phase 3:** Add Google provider (if safety filter testing passes).
- **Phase 4:** Self-hosted Llama via a local OpenAI-compatible server
(vLLM, Ollama, etc.).

