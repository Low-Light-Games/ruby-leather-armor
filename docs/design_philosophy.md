# Design Philosophy

Guiding principles behind the architecture of this application. These are
not rules to follow blindly — they are patterns that emerged from building
the system and observing what worked. When a new decision feels uncertain,
check it against these principles first.

---

## 1. AI for judgment, code for certainty

Use AI where the outcome is uncertain, subjective, or requires contextual
reasoning. Use code where the result can be computed deterministically.

**AI is better at:** interpreting player intent, adjudicating edge-case
rule interactions, writing narrative prose, deciding what's
macro-significant, evaluating whether a context changed.

**Code is better at:** rolling dice, applying HP changes, validating JSON
schemas, routing pipeline steps, merging beacon results, looking up
stat blocks, enforcing clamping bounds.

The temptation is to let the AI do everything because it *can*. Resist
this. Every task handed to the AI is a task that can hallucinate, cost
tokens, and fail silently. If the answer is computable, compute it.

The inverse is also true: don't write brittle regex parsers for tasks
where you cannot enumerate all valid inputs. If you can't be 100% certain
a code-only solution covers every case, the AI will do a better job.

**Corollary: distrust clever regexing.** Pattern matching against player
input is brittle for the same reasons code-first solutions fail on
uncertain inputs. Temporal conjunctions ("then", "after that", "once
done") seem parseable by regex, but edge cases are unbounded: "I then
cast fireball" should not split, "I fire, then reload" is ambiguous.
If the input space is natural language, use AI. The Sequencer step
exists because regex-based compound action detection would be fragile
in exactly the ways that matter most.

---

## 2. Honor system

The player is trusted. They roll their own dice and report the results.
They set their own starting gold. They choose their own feats and spells.
This is a deliberate design choice, not an oversight.

**Why:** this is a tabletop RPG emulator, not a competitive multiplayer
game. The joy of tabletop is agency and trust between the player and the
DM. A system that second-guesses every player input ("did you really roll
a 19?") is adversarial and breaks immersion.

**Where we draw the line:** the SanityChecker validates that the
player *possesses* the spells, feats, and items they reference — not that
they used them correctly. This is the same standard a real DM applies:
"you can't cast Fireball because it's not on your spell list" is fair;
"I don't believe you rolled a 17" is not.

**Consequence:** the system is not cheat-proof. A player who lies about
their rolls will get incorrect outcomes. This is acceptable — the same
is true at a real table.

---

## 3. Structured decomposition over model reasoning

Do not rely on a single model's ability to reason through a complex,
multi-part task. Instead, break the task into focused steps and let cheap
models deliver good results on each one.

**The pattern:** when a prompt tries to do too many things at once,
accuracy degrades on all of them. The fix is never "use a smarter model"
— it's "split the prompt." A $0.10/M-token nano model that receives a
focused, 800-character prompt outperforms a $2.00/M-token full model that
receives a bloated, 13,000-character prompt doing eight things.

**In practice:**
- The original single-prompt DM was replaced by a 10+ step pipeline
- Triage was split into Sanitize + Classify when both tasks degraded
- Intent was split from Beacon when context routing
  suffered
- MechanicalEvaluation was split from Verdict when roll arbitration
  conflated with roll identification
- Context updates were decoupled from narrative so they work from
  unambiguous factual outcomes

**The principle:** our structured "way of thinking" — the pipeline
topology, the step sequencing, the data contracts between steps — is
itself a form of reasoning. We externalize the chain of thought into
architecture rather than hoping the model produces one internally. This
makes the system model-agnostic: if a cheaper model appears tomorrow,
we can slot it in without redesigning the flow.

---

## 4. When in doubt, add a toggle

Every significant behavioral choice should be admin-configurable without
code changes. Getting the most out of AI requires empirical tuning, and
the feedback loop must be fast: change a setting, observe the result,
adjust.

**Current toggles:**
- `pipeline_mode` — budget (multi-step) vs. edge (single-call)
- `interpreter_scope` — all domains vs. filtered
- `guardrail_mode` — code-based vs. AI-based validation
- `narration_mode` — parallel vs. subjugated output
- `async_pipeline` — synchronous vs. Sidekiq background execution
- `sanitization_threshold` — danger score cutoff (0-100)
- `verbose` / `pacing_words_min` / `pacing_words_max` — narration length
- `temperature` — creativity/randomness
- Per-step model selection and token budgets
- `directed_dm` — per-adventure narrative steering
- `embellisher_mode` — story enrichment behavior

**Why toggles over code branches:** a developer changing an `if` statement,
deploying, and observing is a 10-minute cycle. An admin flipping a toggle
in the UI is a 10-second cycle. When you're tuning AI behavior — which
requires dozens of iterations — that 60x speedup is the difference between
"we tuned it" and "we shipped the first thing that worked."

**Corollary:** when adding a new capability that has more than one
reasonable implementation (code vs. AI, parallel vs. sequential, cheap
vs. expensive), don't pick one — implement both behind a toggle and let
the admin discover which works better through observation.

---

## 5. Correctness over speed

When forced to choose between a faster pipeline and a more accurate one,
choose accuracy. This is a turn-based game — the player is not waiting
for a real-time response. A 12-second turn that gets the rules right is
better than a 4-second turn that miscalculates damage.

**Manifestations:**
- Mechanics are resolved *before* narration, preventing narrative bias
  from corrupting outcomes
- Truncated AI responses are hard errors, not gracefully degraded —
  partial JSON is worse than no JSON
- NPC rolls are app-side deterministic, not AI-generated
- The Verdict step produces structured mutations, not natural language —
  `{ "hp_change": -8 }` is unambiguous, "takes some damage" is not

**Exception:** the Edge Pipeline deliberately trades accuracy for speed.
It exists as an opt-in mode for scenarios where latency matters more
than precision (demos, low-stakes play). The default is always the
accurate path.

---

## 6. Mechanical honesty

The AI is the storyteller, not the physicist. It decides *what happens
narratively*; the application decides *what the numbers say*.

- The AI identifies which creature appears → the app creates it from a
  real bestiary entry with deterministic HP
- The AI says the NPC attacks → the app rolls d20 + real modifier from
  the creature's stat block
- The AI says the player takes damage → the app clamps HP between
  `-CON` and `max_hp`
- The AI says a spell is cast → the app checks the character sheet for
  that spell

The AI can't fudge dice, invent stat blocks, or ignore HP bounds. This
makes the game mechanically trustworthy even when the narrative is
creative.

---

## 7. Immersion preservation

Technical failures, system internals, and debug data should never leak
to the player.

- All errors become *"The Dungeon Master is momentarily distracted..."*
- Token budgets, model names, step names, and pipeline UUIDs are
  admin-only
- Raw micro-context JSON is hidden behind an admin-only collapsible
- The scene summary translates internal state into a natural-language
  status line for the player
- The Chronicler produces a DM Brief instead of exposing the raw story
  premise — the narrator never sees unrevealed plot secrets

The admin sees everything: full AiLog records, request bodies, reasoning
fields, pipeline traces. The player sees only what a tabletop player
would see: the DM's words and the dice they need to roll.

---

## 8. Audit everything

Every AI call is logged with its full request, response, parsed output,
model used, and the AI's own reasoning. Every mutation is traceable to
the verdict that produced it. Every plot state change records which clues
were discovered and why.

**Why:** AI behavior is non-deterministic. When something goes wrong (and
it will), the only way to diagnose it is to replay the exact inputs the
model received and the exact outputs it produced. Without comprehensive
logging, debugging AI is guesswork.

**The `reasoning` field:** every AI step's JSON schema includes a
`reasoning` field. This costs ~20-40 tokens per call (negligible) and
provides the model's own explanation of its decision. When a verdict is
wrong, the reasoning field often reveals *why* — "I assumed the player
had Improved Grapple" is immediately actionable.

---

## 9. Incremental decomposition

Don't preemptively split things. Build the simplest version that works,
observe where it breaks, and split at the fault line.

**The history:**
- Started with a single DM prompt → split into pipeline steps when
  accuracy degraded
- Started with 3 micro-contexts → expanded to 6 when exploration, rest,
  and inventory didn't fit
- Started with combined Triage → split into Sanitize + Classify when
  both tasks suffered
- Started with monolithic Intent → split into Intent + Beacon when
  context routing failed
- Started with synchronous HTTP → added async Sidekiq when connection
  pool exhausted

Every split was motivated by observed failure, not theoretical purity.
This avoids premature abstraction while ensuring that when complexity is
added, it solves a real problem.

**Corollary:** when splitting, preserve the old path behind a toggle
(see principle 4). The new approach might not be better — you need the
ability to compare.

---

## 10. Coexistence over migration

When introducing a new approach, don't rip out the old one. Keep both
paths alive behind a toggle and let observation determine which wins.

- Sync and async pipelines coexist (`async_pipeline` toggle)
- Budget and Edge pipelines coexist (`pipeline_mode` toggle)
- Code and AI guardrails coexist (`guardrail_mode` toggle)
- All-domain and filtered beacon modes coexist (`interpreter_scope` toggle)
- Parallel and subjugated narration coexist (`narration_mode` toggle)

This principle is a direct consequence of principles 4 and 9: if you
toggle everything and split incrementally, coexistence is the natural
result. The old path is your safety net and your control group.

---

## 11. Prompt isolation

Each AI step receives exactly the context it needs — no more. A combat
evaluation doesn't see the social context. A sanitization check doesn't
see the character sheet. A classifier doesn't see the rules manifest.

**Why:**
- Reduces token cost (smaller prompts = fewer input tokens billed)
- Focuses the model's attention (less irrelevant context = fewer
  distractions)
- Makes prompts easier to reason about (a developer can read one template
  and understand everything the model sees)
- Enables per-step model selection (a focused prompt can use a cheaper
  model)

**Mechanisms:**
- ERB templates are separated from Ruby logic
- Domain-specific partials load only for the relevant domain
- `CharacterBlock.for(sheet, category:)` filters the character sheet to
  domain-relevant stats
- Selective context updates include only affected + active contexts
- The Chronicler produces a DM Brief instead of passing the full premise
  to the narrator

---

## 12. Time as a higher-order context

Time of day, adventure day, and light conditions are tracked as a
code-managed context (`time_context`) separate from the six domain-specific
micro-contexts. Time is "above" the domains — it affects all of them but
belongs to none of them.

**Key decisions:**
- TimeKeeper estimates time after Verdict (when the outcome is known), not
  during intent (when it's still speculative)
- Time estimation is code-first: journeys to known destinations use
  deterministic distance/speed/terrain math; combat, rest, and Take 20 use
  fixed values. AI is only called for freeform actions (wait, craft, etc.)
- The clock is advanced by GameClock (a code-only utility), never by AI —
  deterministic hour arithmetic eliminates desynchronization
- Light conditions (dawn/day/dusk/night) are derived from `current_hour` via
  a fixed mapping in GameClock, ensuring consistency
- Harbinger (encounter utility) is consulted before clock advancement —
  it may interrupt the passage, and the clock is updated with *actual*
  elapsed hours, not estimated
- Terrain speed modifiers are admin-configurable via DmConfig, with PF1e
  defaults (road 1.0x, forest 0.5x, mountain 0.25x, etc.)
- `time_context` is initialized during adventure creation from story cues
  (e.g., "at dawn" → hour 6) and defaults to hour 8 (morning)

This separation means time tracking works universally — for traversal, rest,
crafting, waiting, Take 20, or any other passage of time — without requiring
each domain's beacon to understand time mechanics.

---

## 13. Naming: whimsical for AI, functional for code

Pipeline steps and modules follow a naming convention that makes their
nature immediately obvious:

**AI steps get character/persona names** — evocative, easy to remember,
scoped to one responsibility. If you can't name it without a compound
word, the step is probably doing too much.

Current AI step names: PlayerInterpreter, Beacon, Sequencer, Verdict,
MechanicalEvaluation, RollQualifier, SanityChecker (capability check +
world consistency check), TimeKeeper, Chronicler, Narrate, Sanitize,
Classify, DM Query.

**Code-only steps get role/object names** — functional, clearly
non-creative, conveying "no AI judgment here."

Current code-only names: Stagehand, CoreResolver, GameClock, Harbinger,
Mutations.

**Why this matters:** when debugging a pipeline, the name tells you
whether a step's output is deterministic (code) or probabilistic (AI).
If the Stagehand produced wrong data, it's a code bug. If the Verdict
produced wrong data, it's a prompt or model issue. The naming convention
encodes this diagnostic shortcut into every conversation about the
pipeline.

---

## 14. Document the why, not just the what

Design documents explain the reasoning behind decisions, not just the
decisions themselves. Every design decision in `pipeline_steps.md`
includes a "Why" and a "Trade-off accepted" section. Commit messages
describe the problem being solved, not just the files changed.

**Why:** six months from now, the code will be obvious ("it calls
`run_sanitize` then `run_classify` in parallel"). What won't be obvious
is *why* it was split, what the alternatives were, and what trade-offs
were accepted. Without that context, future changes risk re-introducing
problems that were already solved.

**The documents:**
- `docs/design_philosophy.md` — this file; the guiding principles
- `docs/pipeline_steps.md` — what each step does, why it exists, how
  it connects
- `docs/pipeline_model_selection.md` — model recommendations per step
  with cost analysis
- `docs/async_pipeline_design.md` — the specific problem and solution
  for async execution
