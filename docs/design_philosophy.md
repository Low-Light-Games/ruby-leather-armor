# Design Philosophy

Guiding principles behind the architecture of this application. These are
not rules to follow blindly — they are patterns that emerged from building
the system and observing what worked. When a new decision feels uncertain,
check it against these principles first.

---

## The fundamental tradeoff: freedom for graphics

This is a text-only adventure. There are no sprites, no animations, no
visual fidelity to fall back on. What justifies that constraint is one
thing: unboundedness. A graphically rich game can look beautiful but must
restrict the player to pre-authored paths, scripted encounters, and
enumerated choices. An AI-driven text game looks plain but can respond to
anything the player imagines.

That tradeoff — graphics for freedom — is the entire value proposition.
Every design decision must be evaluated against it. When a problem tempts
you toward a rigid, deterministic solution that clips player agency, stop
and ask: does this preserve the freedom that justifies the medium? If it
doesn't, the solution is wrong regardless of how clean the code is.

The principles that follow (especially #1, "AI for judgment, code for
certainty") exist to make the system *reliable*, not *restrictive*.
Deterministic code handles dice rolls, HP math, and clock arithmetic
because those have objectively correct answers. But the moment determinism
encroaches on what the player can attempt, how the world responds, or what
outcomes are possible, the system has traded away the only thing it has.

**The test:** if a player tries something surprising and the system shrugs
it off with a canned response — or ignores it because no code path handles
it — the design has failed. Not because of a bug, but because it violated
the core tradeoff. When in doubt, lean toward the AI path. A hallucination
can be corrected; a missing degree of freedom cannot be experienced.

---

## 1. AI for judgment, code for certainty

Use AI where the outcome is uncertain, subjective, or requires contextual
reasoning. Use code where the result can be computed deterministically.

**AI is better at:** interpreting player intent, adjudicating edge-case
rule interactions, writing narrative prose, deciding what's
macro-significant, evaluating whether a context changed.

**Code is better at:** rolling dice, applying HP changes, validating JSON
schemas, routing pipeline steps, merging domain evaluation results,
looking up stat blocks, enforcing clamping bounds.

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

**Corollary: define prompt ownership positively.** A prompt should state
what its step or domain *does own*, narrowly and concretely. Prefer
positive scope over long lists of forbidden behaviors. Use explicit
"do not do X" language only for repeated, high-cost confusions where the
boundary must be hard, such as traversal vs. stealth.

**Example:** inventory should talk about concrete item-state changes
(gain, lose, equip, consume, loot), not "resources" in the abstract.
Traversal should describe movement and location change, while exploration
explicitly owns stealth-style field actions.

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
- Evaluation was consolidated from 6 parallel beacons + sequential
  MechanicalEvaluation + RollQualifier into a single UnifiedEvaluation
  call when the multi-step cost outweighed the isolation benefit
- MechanicalEvaluation was originally split from Verdict when roll
  arbitration was conflated with roll identification
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
- `guardrail_mode` — code-based vs. AI-based validation
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

**Errors are first-class audit artifacts:** in production and staging,
every real error must be observable. The failure path uses
`ApplicationErrorReporter.notify(exception, context: { ... })` — or
patterns that already delegate to it, such as
`DungeonMaster::Logging#report_error` and `#capture_pipeline_exception!`
— so the exception surfaces in Sentry with a context hash rich enough
to replay. This applies even when the surrounding operation is
intentionally degraded rather than aborted: if a step swallows an
`AiError`, a `TokenBudgetExceededError`, or a `StandardError` to keep a
turn flowing (for example, a best-effort fact writer), it still has to
notify before it continues. A play_log entry is never a substitute
for a Sentry notification — play_log exists for in-app debugging and
is easy to miss at a glance, while Sentry is where reliability signal
is actually monitored. Bare `rescue StandardError; nil` is reserved
for true last-resort shims and, when used, must still notify. The rule
is enforced by the always-applied Cursor rule
[`.cursor/rules/error-reporting-sentry.mdc`](/.cursor/rules/error-reporting-sentry.mdc);
this section is the design rationale behind it.

**Why:** silent failures are the worst-case AI bug, because AI pipelines
degrade gracefully by design (per §1, honor system verdicts; per §17,
don't code-fix AI problems). The same properties that make a pipeline
robust to individual model hiccups — best-effort steps, lossy caches,
fallback paths — also make it possible for a whole class of failures to
never surface. Sentry notification is the guarantee that "degraded"
never becomes "invisible": the data may be lossy, the error signal
must not be.

---

## 9. Incremental decomposition of AI pipeline steps

Don't preemptively split AI calls or pipeline steps into separate
interactions. Start with the simplest unified approach that works,
observe where it degrades, and split at the fault line.

This principle is scoped to **AI interactions and pipeline topology** —
where a split means a new model call, a new prompt, or a new evaluation
step. It is not a general argument against refactoring code structure:
extracting Ruby classes, decomposing service objects, and cleaning up
code organization are ordinary engineering hygiene and do not require
observed AI failure to justify.

**The history:**
- Started with a single DM prompt → split into pipeline steps when
  accuracy degraded
- Started with 3 micro-contexts → expanded to 6 when exploration, rest,
  and inventory didn't fit
- Started with combined Triage → split into Sanitize + Classify when
  both tasks suffered
- Started with monolithic Intent → split into Intent + Beacon when
  context routing failed
- Started with synchronous HTTP → moved to async Sidekiq permanently
  when connection pool exhaustion caused 504 timeouts under real load

Every AI pipeline split was motivated by observed failure, not
theoretical purity. Adding a new model call or evaluation step requires
evidence that a unified call was ineffective — accuracy degradation,
token budget ceiling, inability to tune the model independently, or
debuggability collapse.

**Corollary:** when splitting an AI step, preserve the old path behind
a toggle (see principle 4). The new approach might not be better — you
need the ability to compare.

**Exception — retiring a proven path:** once a new approach has been
validated in production and the old path adds complexity without
comparison value, it can be retired. The synchronous HTTP pipeline is
an example: after async Sidekiq proved strictly superior (no timeout
risk, better UX, identical player experience), the sync path was
deleted rather than kept behind a dead toggle.

---

## 10. Coexistence over migration

When introducing a new approach, don't rip out the old one. Keep both
paths alive behind a toggle and let observation determine which wins.

- Code and AI guardrails coexist (`guardrail_mode` toggle)

This principle is a direct consequence of principles 4 and 9: if you
toggle everything and split incrementally, coexistence is the natural
result. The old path is your safety net and your control group.

**Waiver.** Coexistence is the default, not a mandate. When a path has
been demonstrably low-confidence or effectively broken, we may retire it
outright instead of maintaining the toggle. Two precedents: the
`narration_mode = "subjugated"` branch (retired in favor of parallel
output), and the pre-facts-store World Consistency Check
(retired in favor of the narrative facts store, see
docs/pipeline_steps.md Decision 37).

**Note:** the synchronous HTTP pipeline is an intentional exception.
After async Sidekiq was validated in production, the sync path was
retired entirely — it offered no meaningful comparison value and keeping
it would have required maintaining two diverging code paths. Coexistence
is the default strategy; retirement is acceptable when the old path is
strictly dominated and confidence is high.

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

**Deliberate exception:** the Unified Evaluation mode (default) intentionally
sends all six micro-contexts, the full character block, and the complete rules
manifest to a single AI call. This trades prompt isolation for cross-domain
coherence — the model can see flanking context when adjudicating a Perception
roll, or social attitude when deciding combat consequences. This is acceptable
because: (a) it requires at minimum a mid-capable model (gpt-4.1-mini or
equivalent) with a sufficient context window, (b) the legacy standard path
remains available for rollback or per-domain model tuning, and (c) the rest
of the pipeline (sanity checks, verdict, narration, context updates) remains
isolated.

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
- In combat, TimeKeeper consults canonical post-mutation combat truth rather
  than trusting the lagging cached combat snapshot, because it runs after
  mutations but before context refresh
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
the evaluation step to understand time mechanics.

---

## 13. Naming: whimsical for AI, functional for code

Pipeline steps and modules follow a naming convention that makes their
nature immediately obvious:

**AI steps get character/persona names** — evocative, easy to remember,
scoped to one responsibility. If you can't name it without a compound
word, the step is probably doing too much.

Current AI step names: Sequencer, SanityChecker
(capability check + world consistency check), Mechanic, Combat GM, Momentum,
Social Expansion, Chronicler, Narrate, Intake, DM Query.

**Code-only steps get role/object names** — functional, clearly
non-creative, conveying "no AI judgment here."

Current code-only names: Stagehand, AdventureLoopResolution, GameClock, Harbinger,
Mutations, World Turn, CombatMechanicResolution.

**Why this matters:** when debugging a pipeline, the name tells you
whether a step's output is deterministic (code) or probabilistic (AI).
If the Stagehand produced wrong data, it's a code bug. If Mechanic or
Combat GM produced wrong data, it's a prompt or model issue. The naming convention
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
- `docs/pipeline_steps.md` — design decisions + model tier reference + configuration
  with cost analysis
- `docs/async_pipeline_design.md` — the specific problem and solution
  for async execution

**Code comments: by exception, not by default.** The "document the why"
instinct stops at the source-file boundary. Code is expected to carry
its own explanation — well-named methods, memoized readers, predicate
methods, value objects whose class names and attribute names spell out
their shape. A comment that restates what the next few lines do is
noise: it drifts out of sync with the code, trains readers to skim
rather than read, and usually signals that the code below deserved a
better name or a smaller surface.

Comments earn their place only when they capture something the code
cannot: a non-obvious invariant, a trade-off deliberately accepted, an
external constraint (API quirk, DB limitation, §-rule from this
document), or a short pointer to the `docs/` section that owns the
full rationale. When in doubt, rename the method, extract a class, or
cite a design doc instead of adding a paragraph. The durable "why"
belongs in the documents listed above, not scattered across service
files where it will silently go stale.

---

## 15. No text-parsing fallbacks

When a code path relies on structured data — a tag on the `AdventureLoop`,
a parsed JSON field from an AI step, a column in the database — do **not**
add a regex or string-match fallback that attempts the same thing on raw
text "just in case."

**Why:**
- A fallback that shadows the primary path **diminishes the value of the
  better check.** If the regex fires 20% of the time, the structured path
  was only 80% worth building. The investment in a clean data flow only
  pays off when the system actually relies on it.
- Fallbacks **mask bugs.** If the structured data is missing because a
  step forgot to write it, the fallback silently produces a degraded
  result. The bug surfaces as a subtle quality regression weeks later
  instead of an immediate, diagnosable failure.
- Fallbacks **make code harder to reason about.** A reader seeing two
  paths — one clean, one heuristic — cannot easily tell which one
  actually fires in production, what conditions trigger the fallback,
  or whether the fallback's behavior even matches the primary path's
  contract.

**The rule:** if the structured data is absent, log the gap and fail
visibly. Return an empty result, skip the step, or raise — whatever
makes the failure observable. Do not silently degrade into a broken
heuristic.

**Example:** Warmaster needs creature names and counts to spawn
enemies. The `encounter_expand` AI step produces a structured
`creatures` array stored on the `AdventureLoop`. If that data is
missing, Warmaster logs "no creatures_data" and returns zero creatures
— it does *not* fall back to regex-parsing the encounter description.
This ensures that if `encounter_expand` ever stops producing the
`creatures` field, the failure is immediately visible in logs and in
gameplay, rather than silently spawning one creature instead of four.

---

## 16. AdventureLoop: semantic layer over the pipeline

`PipelineRegistryEntry` is the mechanical/operational record — it tracks timing,
status transitions, and AI call logs for one async DM pipeline execution (keyed by
`registry_entry_uuid`). `AdventureLoop` is the semantic
record — it captures what happened from the player's perspective for a
single sequenced action.

**Key design:**
- `PipelineRegistryEntry` 1:N `AdventureLoop` — one loop per sequenced action
  within the same registry entry
- Each loop carries `tags` (boolean flags like `took_20`,
  `encounter_triggered`), `data` (structured key-value pairs like
  `encounter_entry_id`, `hours_elapsed`), and a `timeline` (ordered
  step summaries)
- Pipeline steps write to `@loop` at their natural point; downstream
  steps read from it. This replaces fragile method-argument threading
  with explicit, persistent writes.
- The loop is the **single source of truth** for cross-step data. When
  TimeKeeper needs to know if the player chose Take 20, it checks
  `@loop.tagged?("took_20")` — it does not parse text from verdict
  outcomes. When Warmaster needs creature data, it reads
  `@loop.get("encounter_creatures")` — it does not regex-parse
  encounter descriptions.

**Consequence:** adding a new piece of cross-step data is a one-line
`@loop.set(...)` in the producing step and a one-line `@loop.get(...)`
in the consuming step. No method signatures change, no hashes need new
keys threaded through five layers of calls.

---

## 17. Don't code-fix AI problems

When AI output contains errors, inconsistencies, or duplications, the fix
belongs in the prompt — not in post-hoc code that pattern-matches the
output.

**The anti-pattern:** AI step X produces duplicated or contradictory data.
A downstream code step string-matches the output, detects the problem, and
silently removes or rewrites it. The code is now a heuristic parser of AI
output — exactly the brittleness Principle 1 warns against.

**Why this fails:**

- The code can only match patterns it anticipates. The AI will find new
  ways to be inconsistent that the code doesn't handle.
- Silent correction masks the upstream problem. The AI keeps producing bad
  output, but nobody notices because the code "fixes" it.
- The code becomes load-bearing in ways that are hard to reason about.
  Removing or changing the heuristic breaks things in non-obvious ways
  because production silently depends on it.

**The rule:** code may only intervene in AI output when it is **100%
authoritative** — when the intervention is based on deterministic data
(character sheet stats, database records, game rules with no ambiguity)
rather than on matching text or numbers the AI generated.

**Prompt-scope corollary:** when an AI step keeps emitting cross-domain or
contradictory output, first tighten the prompt around what that step
*does own*. Prefer narrow, positive scope over long lists of forbidden
behavior. Use explicit negative instructions only for repeated,
high-cost confusions where the ownership boundary must be reinforced
(for example traversal vs. stealth).

**Cheap-model policy (required):** treat prompt edits as contract simplification,
not warning accumulation.
- Prefer edits that **remove responsibility** from the model (move deterministic
  state handling to code that already owns it).
- Prefer edits that **replace ambiguous instructions** with narrower contracts.
- Prefer edits that **split overloaded prompts** into smaller scoped steps.
- Do **not** treat additive "DO NOT ..." lists as a primary fix when a
  deterministic seam already owns the data (counts, HP, roster shape, turn order).
- If a prompt-only fix cannot be expressed as simplification/replacement, stop and
  look for the owned deterministic seam first.

**Examples:**

- **Correct (deterministic):** `filter_auto_success_rolls!` removes rolls
  where the character's real skill modifier guarantees success. The
  character sheet is ground truth; this is arithmetic, not heuristics.
- **Correct (deterministic):** `apply_mutations` clamps HP between `-CON`
  and `max_hp`. HP bounds are game rules with no ambiguity.
- **Wrong (heuristic):** `deduplicate_rolls!` pattern-matched
  `[skill, type, dc]` on AI output to remove duplicates the AI created.
  The code was guessing which rolls are "the same" based on string
  comparison of AI-generated skill names. Removed in favor of a stronger
  MechEval prompt instruction.
- **Wrong (heuristic):** domain-authority dedup that resolves conflicting
  DCs by checking which domain "owns" a skill name. This is still
  string-matching AI output; the right fix is a prompt that prevents the
  conflict.

**When you see duplicate or contradictory AI output:** improve the prompt,
add examples, or restructure the step inputs so the AI doesn't produce the
problem. If the problem persists, log it as a warning for observability —
but do not silently alter the output.

---

## 18. Micro-contexts as adventure state checkpoints

The micro-context fields (`traversal_context`, `combat_context`,
`social_context`, `exploration_context`, `rest_context`,
`inventory_context`) are the adventure's official world state. Every
pipeline step that needs world state reads from the current snapshot.
Every turn ends by writing an updated snapshot. The adventure is
structured like a linked list: each node contains everything needed to
produce the next, with no dependency on what came before.

**The problem this solves:** AI wrapper products face a predictable failure
mode. The context window fills with message history, the model attends to
older turns inconsistently, and hallucinations about "what already
happened" accumulate as the adventure grows longer. Sending the full
conversation is also expensive — prompt size scales with session length
rather than staying bounded.

**The design response:** the pipeline does not pass message history to AI
steps. It passes the current micro-context snapshot. A model generating
narrative for turn 80 has the same clean, bounded input as one generating
narrative for turn 1. Long adventures do not become harder or less
reliable to reason about.

**Single-writer principle (JSONB micro-contexts):** ContextUpdate is the primary writer for the six `*_context` JSONB fields. Documented exceptions and co-writers must stay explicit so drift stays observable:

- **Combat start:** `DungeonMaster::Battlefield::PersistCombatStart` writes `combat_context` in one transaction with a new `adventure_battlefields` row and `battlefield_ref` (used by `run_initiative` and `AdventureMechanicalState.auto_finalize_pending_initiative!`).
- **Encounter pause (Path A pending roster):** `DungeonMaster::EncounterWarmasterBridge` may call `DungeonMaster::Utilities::Warmaster.persist_pending_combat!` to persist an NPC-only pending roster before initiative is provided. This is a documented writer because the pause must preserve encounter roster truth before ContextUpdate runs.
- **Mid-combat / missing map (just-in-time):** `DungeonMaster::Battlefield::EnsureForActiveCombat` creates the row + ref the first time something needs a battlefield while `combat_context.active` is true (no batch rake). Invoked from serializers, roll metadata, and patch application so stories can start in combat without initiative.
- **Combat resolution:** `DungeonMaster::Battlefield::ApplyPatches` bumps the battlefield row and syncs `combat_context["battlefield_ref"]["version"]` after Combat GM / world-turn patches. `apply_mutations` may merge `action_economy_delta` into `combat_context` when the Combat GM emits spends.
- **Combat end:** `DungeonMaster::Battlefield::ArchiveCombatEnd` archives the row and updates `last_battlefield_ref` / clears `battlefield_ref`, invoked when micro-context persistence detects `active: true → false`.
- **Adventure UI (combat):** direct sheet endpoints (e.g. equip toggle) may atomically adjust `action_economy` when `combat_active?` — server-authoritative, no AI.

`ContextUpdate` applies **deep merge** for `combat` when persisting micro-context output so partial `combat_state_advancement` payloads do not drop `battlefield_ref`, `last_battlefield_ref`, or `action_economy` by accident.

Deterministic utilities like Warmaster still compute hashes; ContextUpdate receives structured mutations for narrative-driven updates. This pattern limits races where two writers each assume they own the full document.

**Runs before every pause:** ContextUpdate executes before any pipeline
early return that presents a message to the player — initiative prompts,
roll requests, and full narrative responses. If the player never resumes
a paused adventure, the snapshot in the database still reflects reality up to
that moment.

**Self-directed:** ContextUpdate reads the outcome (`what_happened`) and
decides which of the six domains changed. It does not rely on upstream hints.
All six domain schemas are included in every prompt; the AI updates what
changed and carries forward everything else unchanged.

**Context snapshots on AdventureLoop:** after each ContextUpdate run, the
full six-field snapshot is written to `adventure_loop.data["context_snapshot"]`.
This produces a linear progression trail of the world state across every
pipeline action — available in the database for debugging, never re-sent to
the model.

**Context wishes:** if the outcome touches something that doesn't fit any
existing domain, ContextUpdate can emit a `context_wishes` entry. Each wish
is persisted as a `context_wish` play log event, visible in the admin UI as
an amber badge. These are observability signals for future domain design, not
errors.

**World Consistency Check no longer queries micro-contexts.** As of the
narrative facts store cutover (see `docs/pipeline_steps.md` Decision 37),
`sanity_checker_world` reads its dynamic-state input from
`adventure_narrative_facts` (pgvector, top-K by similarity against the
player's intent) rather than from the six `*_context` JSONB fields.
Micro-contexts remain the structured mutation surface for ContextUpdate
and every other consumer that needs domain-typed state; they are simply
no longer the retrieval target of the world sanity gate. This keeps the
§18 single-writer principle intact for the JSONB fields (ContextUpdate
is still the primary writer, with the same documented exceptions above)
while introducing a second, orthogonal store with its own single writer:

- **`adventure_narrative_facts` (pgvector):** sole writer is
  `DungeonMaster::Lore::ApplyResults`, invoked from
  `DungeonMaster::Steps::Stagehand` on every terminal narrative phase
  (`source: "loremaster"`) and from `DungeonMaster::Lore::SeedFromAdventure`
  at adventure creation (`source: "seed"`). No other pipeline step,
  admin tool, or background job mutates this table. A partial unique
  index on `(adventure_id, introduced_at_loop_id, source_idx) WHERE
  source = 'loremaster'` makes idempotent reapply a no-op so the
  lossy-with-Sentry write contract stays safe under higher-layer
  retries.

---

## 19. No ad-hoc data structures

Every piece of data with a fixed shape is a named class — value object,
result object, event payload, presenter output, query result, DTO. Inline
anonymous hashes passed across object boundaries, or `Struct.new(...)` lines
hidden inside service files, are not acceptable. This was called out during
the PR #98 cleanup epic and the pattern is enforced by
`.cursor/rules/no-ad-hoc-structures.mdc`.

**What counts as shaped data:**

- Service return values with more than one field (`Lore::FactsChangeSet`,
  `PipelineFlowResults::AwaitingRolls`, etc.).
- Structured logging payloads — `play_log!` `parsed_response:` hashes,
  `ai_log!` details, Sentry `context:` bags. Operators reading Admin >
  Play Logs need the possible key set documented in one place, not
  scattered across the service.
- Retrieval hits returned by query objects (`Lore::FactHit`), not
  `Struct.new(..., keyword_init: true)` one-liners.

**Template for a value object:**

- Own file under the owning namespace so Rails autoloading picks it up.
- Keyword-argument constructor listing every supported attribute.
- `#to_h` that returns the canonical hash if the consumer is logging
  infrastructure (which serializes to JSON via `to_json`).
- For context bags augmented at call sites, a `#with(**extra)` method
  whose class-level comment documents the supported merge-in keys.
- No runtime behaviour beyond shape: no AR queries, no I/O, no
  `@log.truncate`. Callers pre-normalise what needs normalising.

**Why.** Ad-hoc shapes drift — a key added in one call site and not
another is invisible in a hash literal but obvious in a class diff.
`Struct.new(...)` inline is functionally a class, but its definition is
easy to miss, impossible to annotate with a class-level comment, and
hides supported keys behind a positional-or-keyword signature.

**Narrow exceptions.** Method-local intermediate maps
(`idx -> id` accumulators that never leave the method) and hashes that
are already the canonical ActiveRecord shape (`where(...)`,
`create!(...)`, scope arguments) stay as plain hashes — they're
already typed by the model. When in doubt, wrap it.
