# Pipeline Model Selection Guide

Developer reference for choosing OpenAI models per pipeline step.
Each player message triggers a sequence of AI calls (the pipeline). Because
steps vary drastically in complexity, a single model for every call is
wasteful — cheap steps subsidize expensive ones, or quality suffers where it
matters most.

This guide groups available models into tiers, explains what each pipeline
step actually asks the model to do, and recommends where to spend and where
to save.

---

## Model Tier Reference

Prices are **per 1 million tokens** (input / output).

### Nano tier — dirt-cheap, low latency

| Model | Input | Output | Reasoning | Temp |
|---|---|---|---|---|
| gpt-4.1-nano | $0.10 | $0.40 | No | Yes |
| gpt-5-nano | $0.05 | $0.40 | Yes | No |

Best for: classification, simple JSON output, short-answer tasks.
These models are extremely fast and cheap enough that you can call them
many times per player turn without noticing the cost.

### Mini tier — balanced cost/capability

| Model | Input | Output | Reasoning | Temp |
|---|---|---|---|---|
| gpt-4o-mini | $0.15 | $0.60 | No | Yes |
| gpt-4.1-mini | $0.40 | $1.60 | No | Yes |
| gpt-5-mini | $0.25 | $2.00 | Yes | No |
| o3-mini | $1.10 | $4.40 | Yes | No |
| o4-mini | $1.10 | $4.40 | Yes | No |

Best for: structured reasoning, moderate rule application, context updates.
Mini models sit in a sweet spot: smart enough to follow complex instructions
and produce well-formed JSON, cheap enough to use on multiple steps.

### Full tier — highest non-pro capability

| Model | Input | Output | Reasoning | Temp |
|---|---|---|---|---|
| gpt-4o | $2.50 | $10.00 | No | Yes |
| gpt-4.1 | $2.00 | $8.00 | No | Yes |
| gpt-5 | $1.25 | $10.00 | Yes | No |
| gpt-5.1 | $1.25 | $10.00 | Yes | No |
| gpt-5.2 | $1.75 | $14.00 | Yes | No |
| o3 | $2.00 | $8.00 | Yes | No |

Best for: creative writing, complex multi-factor evaluation, narrative.
Use these where quality directly impacts the player experience.

### Pro tier — maximum compute (use sparingly)

| Model | Input | Output | Reasoning | Temp |
|---|---|---|---|---|
| gpt-5-pro | $15.00 | $120.00 | Yes | No |
| gpt-5.2-pro | $21.00 | $168.00 | Yes | No |
| o3-pro | $20.00 | $80.00 | Yes | No |
| o1-pro | $150.00 | $600.00 | Yes | No |

Best for: nothing in this pipeline, realistically. A single player turn
could cost dollars. Listed for completeness; only consider for offline
batch analysis or debugging a particularly gnarly ruling.

### Legacy tier — avoid for new deployments

| Model | Input | Output | Reasoning | Temp |
|---|---|---|---|---|
| gpt-4-turbo | $10.00 | $30.00 | No | Yes |
| gpt-4 | $30.00 | $60.00 | No | Yes |
| gpt-3.5-turbo | $0.50 | $1.50 | No | Yes |
| o1 | $15.00 | $60.00 | Yes | No |
| o1-mini | $1.10 | $4.40 | Yes | No |

These are superseded by newer models that are both cheaper and smarter.
gpt-3.5-turbo in particular will struggle with Pathfinder rules and
multi-context structured JSON. o1/o1-mini are deprecated in favor of
o3/o4-mini.

---

## Step-by-step Recommendations

### 1. Triage

**What it does:** classifies the player input into a category (combat,
traversal, social, dm_query), assigns a danger score for sanitization,
optionally rewrites the input. Output is a small JSON blob.

**Cognitive demand:** very low. Pattern matching on a single sentence.

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

**Acceptable:** gpt-4.1-mini, gpt-5-mini

**Avoid:** any full or pro model. You're paying 20-100x more for a task
a nano model handles with near-identical accuracy. Reasoning models are
especially wasteful here — internal chain-of-thought tokens inflate the
budget with no benefit for a classification task.

**Token budget:** 300 (non-reasoning) / 1200 (reasoning). Non-reasoning
models are strongly preferred to keep this step fast and lean.

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

### 3. Intent

**What it does:** given the sanitized input and current micro-contexts,
determines what the player is trying to do — the intention, which contexts
are affected, whether mechanics are needed, and whether the action is
macro-significant. Output is structured JSON.

**Cognitive demand:** low to moderate. Slightly more nuanced than triage
(it must understand multi-context actions like "I jump into the sacred
lake to flee my attackers"), but the output is still a small classification.

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

**Acceptable:** gpt-4.1-mini, gpt-5-mini. If multi-context actions are
frequently misclassified with nano, stepping up to mini is worthwhile.

**Avoid:** full and pro models. The task is fundamentally extractive, not
generative. The model reads a player sentence and picks from known
categories — more compute doesn't materially improve this.

**Token budget:** 400 (non-reasoning) / 1600 (reasoning).

---

### 4. Ruling

**What it does:** the most rules-heavy step. Given the player's intent and
the relevant Pathfinder rules, determines what checks are needed, what the
DCs are, what NPC actions occur, and what consequences follow. This step
runs in a **loop** — once per affected context (combat, traversal, social)
— with each iteration receiving a summary of previous rulings.

**Cognitive demand:** high. The model must accurately interpret Pathfinder 1e
rules (attack of opportunity triggers, grapple flowcharts, skill check DCs,
spell effects), compose them correctly with the current context, and produce
structured JSON that the app can act on mechanically. Mistakes here cause
incorrect gameplay.

**Recommended:** o3-mini, o4-mini, gpt-5-mini

These are the sweet spot: reasoning capability for rules interpretation at
moderate cost. The chain-of-thought helps the model "think through" the
rules rather than pattern-match (which often produces plausible but wrong
rulings). gpt-5-mini brings GPT-5-class reasoning at $0.25/$2.00, making
it a strong contender.

**Acceptable:** gpt-5, o3, gpt-4.1

gpt-4.1 is the best non-reasoning option if you want temperature control,
but it lacks chain-of-thought and can miss edge cases in complex rule
interactions. gpt-5 and o3 are reliable but roughly 5-8x the cost of
their mini variants.

**Avoid:**
- Nano models: they will frequently misapply rules, miss AoO triggers,
  or produce malformed ruling JSON on complex multi-check scenarios.
- Pro models: correct but absurdly expensive. o3-pro at $20/$80 per 1M
  tokens for a step that runs multiple times per turn is unjustifiable.
- gpt-3.5-turbo: cannot reliably handle Pathfinder's rule complexity.

**Token budget:** 500 (non-reasoning) / 2000 (reasoning). Because this
step loops, the per-call budget is per ruling context, not per turn. Total
cost scales with the number of affected contexts.

---

### 5. Evaluate

**What it does:** given roll results (player and NPC), the ruling, and the
player's character sheet, determines the mechanical outcome. Did the attack
hit? How much damage? Did the grapple succeed? What conditions apply? Output
is structured JSON with mutations (HP changes, conditions, position updates).

**Cognitive demand:** high. Similar to ruling but with concrete numbers.
The model must correctly apply modifiers, compare against DCs/ACs, handle
critical hit confirmation, damage reduction, spell resistance, etc. Errors
here directly produce wrong HP values, missed conditions, or ignored saves.

**Recommended:** o3-mini, o4-mini, gpt-5-mini

Same reasoning as Ruling: chain-of-thought helps the model work through
arithmetic and conditional logic step-by-step instead of jumping to
(frequently wrong) conclusions.

**Acceptable:** gpt-5, o3, gpt-4.1

**Avoid:**
- Nano models: arithmetic errors are common, especially with multiple
  stacking modifiers. A -nano model might forget to apply Power Attack
  damage bonus while remembering the attack penalty.
- Pro models: not worth the cost.
- gpt-3.5-turbo: struggles with multi-step arithmetic.

**Token budget:** 600 (non-reasoning) / 2400 (reasoning).

---

### 6. Narrate

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

### 7. Micro Context Update

**What it does:** after narration, updates the three micro-context JSONB
fields on the Adventure (traversal, combat, social). Reads the narrative
and mutations, decides what changed, and outputs the new context state as
structured JSON.

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

### 8. Macro Narrative Update

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

## Cost Profiles

The following estimates assume one player turn = triage + intent + 1.5
ruling calls (average context count) + evaluate + narrate + micro context
update, with macro narrative update firing ~20% of the time.

### Budget build (minimize cost)

| Step | Model | Est. cost/turn |
|---|---|---|
| Triage | gpt-4.1-nano | ~$0.0001 |
| DM Query | gpt-4.1-nano | ~$0.0001 |
| Intent | gpt-4.1-nano | ~$0.0002 |
| Ruling | gpt-4o-mini | ~$0.0005 |
| Evaluate | gpt-4o-mini | ~$0.0005 |
| Narrate | gpt-4.1-mini | ~$0.001 |
| Micro Ctx | gpt-4.1-nano | ~$0.0002 |
| Macro Narr | gpt-4.1-nano | ~$0.0001 |
| **Total** | | **~$0.003/turn** |

Quality trade-off: rulings may occasionally misfire on complex
interactions; narrative will be competent but not immersive.

### Balanced build (recommended starting point)

| Step | Model | Est. cost/turn |
|---|---|---|
| Triage | gpt-5-nano | ~$0.0001 |
| DM Query | gpt-5-nano | ~$0.0001 |
| Intent | gpt-5-nano | ~$0.0002 |
| Ruling | o4-mini | ~$0.005 |
| Evaluate | o4-mini | ~$0.005 |
| Narrate | gpt-4.1 | ~$0.008 |
| Micro Ctx | gpt-4o-mini | ~$0.0005 |
| Macro Narr | gpt-4o-mini | ~$0.0002 |
| **Total** | | **~$0.02/turn** |

Quality trade-off: strong rules accuracy from reasoning models, good
narrative from a full-tier model. The bulk of cost comes from narration.

### Premium build (maximize quality)

| Step | Model | Est. cost/turn |
|---|---|---|
| Triage | gpt-4o-mini | ~$0.0002 |
| DM Query | gpt-4.1-mini | ~$0.0005 |
| Intent | gpt-4.1-mini | ~$0.001 |
| Ruling | o3 | ~$0.01 |
| Evaluate | o3 | ~$0.01 |
| Narrate | gpt-5 | ~$0.01 |
| Micro Ctx | gpt-4.1-mini | ~$0.001 |
| Macro Narr | gpt-4.1 | ~$0.003 |
| **Total** | | **~$0.04/turn** |

Quality trade-off: best available accuracy and prose. Twice the cost of
balanced, but every step has headroom.

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

### The ruling step loops

Unlike other steps, Ruling executes once per affected context (combat,
traversal, social). A multi-context action ("I leap into the sacred lake
to escape my attackers") may produce 2-3 ruling calls. Factor this into
cost estimates.

### Context updates compound over time

Micro and macro context updates feed into every future prompt. A cheap
model that produces slightly degraded context will cause downstream
quality loss across all subsequent turns. This is a subtle cost that
doesn't show up in per-turn pricing but can degrade the adventure over
a long session. When in doubt, spend slightly more here.

### Fine-tuning potential

Steps that produce structured JSON with consistent schemas (triage,
intent, ruling, evaluate, context updates) are strong candidates for
fine-tuning on a cheaper base model. Over time, you can collect
AiLog data, curate high-quality examples, and fine-tune gpt-4o-mini or
gpt-4.1-nano to match the accuracy of larger models at a fraction of
the cost. Narration is harder to fine-tune because quality is subjective,
but it's possible with a well-curated dataset.

---

## Non-OpenAI Models

The pipeline currently targets the OpenAI chat completions API exclusively.
This section surveys models from other providers, evaluates their suitability
per pipeline step, and outlines what an integration would require.

### Anthropic (Claude)

**Models:** Claude 4 Opus, Claude 4 Sonnet, Claude 3.5 Haiku

| Model | Input (per 1M) | Output (per 1M) | Context | Notes |
|---|---|---|---|---|
| Claude 4 Opus | ~$15.00 | ~$75.00 | 200K | Top-tier reasoning and prose |
| Claude 4 Sonnet | ~$3.00 | ~$15.00 | 200K | Strong balance of cost and quality |
| Claude 3.5 Haiku | ~$0.80 | ~$4.00 | 200K | Fast, cheap, good at structured output |

**Strengths:**
- Excellent at following complex, multi-constraint instructions — directly
  relevant to the Ruling and Evaluate steps where Pathfinder rules must be
  interpreted precisely.
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

| Step | Fit | Model | Why |
|---|---|---|---|
| Triage | Overkill | Haiku | Works but OpenAI nano is cheaper |
| DM Query | Good | Haiku | Comparable to gpt-4o-mini |
| Intent | Good | Haiku | Reliable classification |
| Ruling | Excellent | Sonnet | Instruction-following shines here |
| Evaluate | Excellent | Sonnet | Careful with modifiers and arithmetic |
| Narrate | Excellent | Sonnet / Opus | Best-in-class prose at the Sonnet tier |
| Micro Ctx | Good | Haiku | Clean JSON output |
| Macro Narr | Good | Haiku / Sonnet | Good judgment on significance |

**Desirability: High.** Claude Sonnet for ruling/evaluate/narrate paired
with OpenAI nano for cheap steps would be a strong hybrid setup. Sonnet's
instruction-following is arguably better than o3-mini for rule-heavy steps,
and its prose rivals gpt-4.1 at a comparable price point.

---

### Google (Gemini)

**Models:** Gemini 2.5 Pro, Gemini 2.5 Flash, Gemini 2.0 Flash

| Model | Input (per 1M) | Output (per 1M) | Context | Notes |
|---|---|---|---|---|
| Gemini 2.5 Pro | ~$1.25 | ~$10.00 | 1M | "Thinking" mode with reasoning |
| Gemini 2.5 Flash | ~$0.15 | ~$0.60 | 1M | Fast, very cheap, thinking optional |
| Gemini 2.0 Flash | ~$0.10 | ~$0.40 | 1M | Predecessor, still available |

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

| Step | Fit | Model | Why |
|---|---|---|---|
| Triage | Excellent | 2.0 Flash | Extremely cheap classification |
| DM Query | Good | 2.5 Flash | Fast Q&A |
| Intent | Good | 2.5 Flash | Cheap and capable enough |
| Ruling | Good | 2.5 Pro | Thinking mode helps with rules |
| Evaluate | Good | 2.5 Pro | Thinking mode helps with arithmetic |
| Narrate | Mediocre | 2.5 Pro | Functional but less immersive prose |
| Micro Ctx | Good | 2.5 Flash | Cheap structured output |
| Macro Narr | Acceptable | 2.5 Flash | Tends to over-include in summaries |

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

| Model | Typical hosted cost (per 1M in/out) | Parameters | Notes |
|---|---|---|---|
| Llama 4 Maverick | ~$0.20 / ~$0.60 | MoE 400B+ | Latest, mixture-of-experts |
| Llama 4 Scout | ~$0.10 / ~$0.30 | MoE ~100B | Smaller, faster MoE |
| Llama 3.3 70B | ~$0.10 / ~$0.30 | 70B | Solid workhorse |
| Llama 3.1 405B | ~$0.80 / ~$2.40 | 405B | Largest dense Llama |

**Strengths:**
- Open weights mean self-hosting is possible, eliminating per-token cost
  entirely (only infrastructure cost). Attractive for high-volume use.
- Hosted providers like Groq and Fireworks offer extremely low latency
  (sometimes faster than OpenAI).
- Llama 4 Maverick is competitive with GPT-4o on many benchmarks.
- Fine-tuning is unrestricted and much cheaper than OpenAI fine-tuning.
  Particularly relevant for steps with consistent schemas (triage, intent,
  ruling).
- No content policy restrictions — the model won't refuse fantasy violence.

**Weaknesses:**
- Instruction-following on complex multi-constraint prompts (ruling,
  evaluate) is noticeably weaker than GPT-4.1 or Claude Sonnet, especially
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

| Step | Fit | Model | Why |
|---|---|---|---|
| Triage | Good | Scout / 3.3 70B | Simple enough task, very cheap |
| DM Query | Good | Scout / 3.3 70B | Straightforward lookups |
| Intent | Acceptable | Maverick / 3.3 70B | May need prompt tuning for multi-context |
| Ruling | Weak | Maverick / 405B | Rule misapplication risk without reasoning mode |
| Evaluate | Weak | Maverick / 405B | Arithmetic and modifier stacking issues |
| Narrate | Acceptable | Maverick | Functional prose, lacks flair |
| Micro Ctx | Acceptable | 3.3 70B | JSON output needs validation layer |
| Macro Narr | Acceptable | 3.3 70B | Tends toward verbose summaries |

**Desirability: Medium-Low for hosted, Medium-High for self-hosted with
fine-tuning.** Out of the box, Llama models aren't competitive with OpenAI
or Claude on the critical steps (ruling, evaluate, narrate). However, if
you invest in fine-tuning — using AiLog data from a higher-quality model
as training examples — a fine-tuned Llama 3.3 70B could potentially match
gpt-4o-mini accuracy on structured steps at near-zero marginal cost. This
is the strongest case for Llama: a long-term cost optimization play.

---

### Mistral

**Models:** Mistral Large, Mistral Medium, Mistral Small, Codestral

| Model | Input (per 1M) | Output (per 1M) | Notes |
|---|---|---|---|
| Mistral Large | ~$2.00 | ~$6.00 | Flagship, strong reasoning |
| Mistral Small | ~$0.10 | ~$0.30 | Fast, cheap |
| Codestral | ~$0.30 | ~$0.90 | Code-optimized, good at JSON |

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
  rules compared to OpenAI or Anthropic models. Ruling accuracy may
  suffer on niche rules (grapple flowchart, combat maneuver bonuses).
- Prose quality on Mistral Large is functional but tends to be more
  utilitarian than GPT-4.1 or Claude. Narration may feel workmanlike.
- The model lineup changes frequently and older models are deprecated
  aggressively, requiring more maintenance.
- Smaller community and fewer third-party tools/libraries.

**Step fit:**

| Step | Fit | Model | Why |
|---|---|---|---|
| Triage | Good | Small | Cheap classification |
| DM Query | Good | Small | Simple Q&A |
| Intent | Good | Small | Pattern recognition |
| Ruling | Acceptable | Large | Functional but less Pathfinder knowledge |
| Evaluate | Acceptable | Large | Decent arithmetic, some edge case misses |
| Narrate | Mediocre | Large | Prose is serviceable but dry |
| Micro Ctx | Good | Codestral / Small | Clean JSON from Codestral |
| Macro Narr | Acceptable | Small | Reasonable judgment |

**Desirability: Low-Medium.** Mistral doesn't clearly outperform OpenAI on
any step, and the smaller model ecosystem means fewer options when
something doesn't work. The best use case would be Mistral Small as an
alternative to gpt-4o-mini on cheap steps, or Codestral for steps that
are pure JSON transformation.

---

### DeepSeek

**Models:** DeepSeek-R1, DeepSeek-V3

| Model | Input (per 1M) | Output (per 1M) | Notes |
|---|---|---|---|
| DeepSeek-R1 | ~$0.55 | ~$2.19 | Chain-of-thought reasoning model |
| DeepSeek-V3 | ~$0.27 | ~$1.10 | General-purpose, very capable |

**Strengths:**
- DeepSeek-R1 is a dedicated reasoning model at a fraction of o3's price.
  For ruling and evaluate steps, the cost savings compared to o3-mini
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

| Step | Fit | Model | Why |
|---|---|---|---|
| Triage | Good | V3 | Cheap, fast classification |
| DM Query | Good | V3 | Straightforward |
| Intent | Good | V3 | Capable classification |
| Ruling | Good | R1 | Reasoning at great price |
| Evaluate | Good | R1 | Chain-of-thought helps arithmetic |
| Narrate | Acceptable | V3 | Functional but English prose can feel stiff |
| Micro Ctx | Good | V3 | Clean JSON output |
| Macro Narr | Acceptable | V3 | Adequate judgment |

**Desirability: Medium-High (with caveats).** DeepSeek offers the best
price-to-reasoning-quality ratio available. R1 on ruling/evaluate is
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
