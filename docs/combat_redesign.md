# Combat Redesign — Deterministic Combat with AI as Escape Hatch

Plan doc for the combat-determinism arc. This is the work that must land
before `Steps::ParallelEvaluation` can be retired, and it overlaps with
that retirement: out-of-combat already runs through
[`Steps::RollRequest`](../app/services/dungeon_master/steps/roll_request.rb);
in-combat is the last caller of the legacy beacon → mech_eval →
roll_qualifier chain.

For the principles behind these decisions see
[Design Philosophy](design_philosophy.md), especially Principle 1
("AI for judgment, code for certainty") and the freedom-for-graphics
opening — combat is the place that principle has been most violated.

---

## Why now

Pathfinder 1e combat is **finite, exact, and testable**. d20 + bonus vs.
AC, flanking is +2, AoO triggers on movement out of a threatened square,
cover gives +4. Every interaction has a deterministic answer. Today's
[`Steps::CombatGm`](../app/services/dungeon_master/steps/combat_gm.rb)
asks an LLM to do that arithmetic — the worst possible use of a
stochastic system.

Three concrete pains:

1. **Cost is quadratic in big battles.** NPC fan-out
   ([`world_turn` combat advancement](../app/services/dungeon_master/world_turn/combat_advancement.rb))
   is one AI call per acting NPC per round. A 6-creature encounter with
   8 rounds is ~50 calls just for the NPC turns, before the player even
   acts.
2. **Latency for the common case.** A "swing your sword" turn is a full
   beacon → mech_eval → roll_qualifier → roll → combat_gm chain.
   Five sequential AI calls for the most predictable possible action.
3. **Quality drift.** The model occasionally picks the wrong attack
   option, mis-applies flanking, or invents DCs. Code can't be wrong
   about whether a square is flanked.

Out-of-combat is already in good shape after the RollRequest arc
(PRs #115, #116, #117). Combat is now the bottleneck.

---

## End state

After this arc:

- **Common case in combat is AI-free.** Player picks an attack, ability,
  spell, or movement from a combat HUD. Code resolves it. Zero AI calls.
- **NPC turns are AI-free.** Bestiary creatures carry a small
  `behavior_policy` describing their preferred actions and triggers.
  A deterministic engine walks the policy each round.
- **Free text is the escape hatch.** Anything the player types in the
  chat box during combat — "I tip the brazier into them", "I try to
  talk them down", "I swing from the chandelier" — routes through
  `Steps::CombatRollRequest`, which inherits the deterministic state
  (action economy, flanking, threats, position) and emits a single roll
  with the same flat shape as out-of-combat RollRequest.
- **Narration is its own AI step.** One `combat_narrator` call per round
  produces flavor over the structured deterministic round log. Tuned
  for a different voice from the default narrator.
- **`ParallelEvaluation` is retired.** Out-of-combat = RollRequest.
  In-combat default = deterministic. In-combat free text =
  CombatRollRequest. Nothing else needs the legacy chain.

---

## Confirmed design decisions

These were locked in conversation before this doc was written. Capturing
them so future-us doesn't re-litigate.

| Question | Decision |
|---|---|
| Narrator economics | One AI call per round, **its own step** (`combat_narrator`), separate prompt/budget/model from the default `narrate` step, tuned for combat voice. |
| Behavior-policy shape | **Start small.** v1 schema covers preferred attacks (e.g. "javelin at range, longsword in melee"), morale (flee threshold), and an extensible `ability_triggers` slot. Grow based on playtest. |
| Action economy UI | **Expose during combat.** Chips for Standard/Move/Swift/Free, filled = available, hollow = spent. Combat-mode textarea placeholder explains it's for creative use beyond standard attacks/maneuvers. |
| Grid authority migration | **One-pass.** Grid becomes canonical for `(x, y, facing)`. Movement actions update the grid synchronously before the resolver fires. AI-described movement parses into the same structured ops. |

---

## What active combat depends on today

Mapping the surface area we have to preserve or replace. From
[`adventure_loop_resolution.rb`](../app/services/dungeon_master/adventure_loop_resolution.rb),
[`combat_gm.rb`](../app/services/dungeon_master/steps/combat_gm.rb),
[`phases/mech_eval_phase.rb`](../app/services/dungeon_master/steps/phases/mech_eval_phase.rb),
and [`phases/combat_mechanic_resolution.rb`](../app/services/dungeon_master/steps/phases/combat_mechanic_resolution.rb):

1. **`CombatMechanicResolution`** — the deterministic post-AI pass that
   resolves `attack_option_id` → attack mode/defense kind/damage,
   computes the attack DC from the named target via
   `ParticipantLookup.defense_dc_for_target!`, resolves saving-throw
   `dc_formula`, and filters NPC actions to AoO only. **This stays.**
   The new combat path uses it as a library, just like the legacy chain
   does.
2. **`merged[:mechanical_summaries]` / `merged[:consequences]`** —
   Combat GM's prompt seeds. After this arc, those come from the
   structured deterministic round log instead of from a per-domain
   evaluator response.
3. **`ensure_damage_metadata_for_active_hit!`** — legacy retry path that
   re-invokes `build_mech_eval_prompts(["combat"], ...)` when an attack
   roll lands but lacks `damage`/`source_type`/etc. With deterministic
   resolution, this whole path becomes unreachable and gets deleted in
   PR-I.
4. **Combat-start hand-off** —
   `intent[:domain_results]["combat"][:transition]` + `combatants`
   triggers Warmaster prep. RollRequest's adapter already mirrors this
   shape, so combat START via RollRequest already works. No change here.

---

## PR sequence

Each PR ships independently and behind nothing more than a small toggle
or a UI affordance. No PR breaks combat for users who don't opt in to
new surfaces.

### PR-A — Action economy state + combat HUD chips (read-only)

**Goal:** surface what's already implicit, without changing flow yet.

**Scope:**
- `Adventure#combat_action_economy` (or per-turn state on the active
  combat row) tracking `{ standard: bool, move: bool, swift: bool, free: ∞ }`.
- Reset at turn start, decrement when an action is taken (today: by the
  AI verdict; later: by the deterministic resolver).
- React combat HUD renders chips with hover tooltips.

**Ship criteria:**
- Chips render correctly during a combat round.
- Specs cover the reset/decrement state machine.
- Zero behavior change to AI flow.

### PR-B — Deterministic player attack endpoint + button

**Goal:** first user-visible AI-free combat path.

**Scope:**
- `POST /adventures/:id/combat_action` with
  `{ kind: "attack", attack_option_id, target_id }`.
- Resolver: roll d20, add attack bonus from sheet, compare to target AC
  (sheet for player-side, creature_sheet for NPC-side), roll damage on
  hit, apply HP delta, emit `action_event`, decrement action economy.
- Frontend: render attack-option buttons in the combat HUD, wired to the
  endpoint.
- Free text in the chat box during combat **still routes through
  `Steps::CombatGm`** — escape hatch is the existing pre-arc path until
  PR-E.

**Ship criteria:**
- One real combat encounter playable end-to-end via buttons.
- Specs cover hit/miss, damage, HP delta, action-economy decrement,
  `action_event` emission.
- Free-text path unchanged.

### PR-C — Grid as canonical position source (one-pass)

**Goal:** make `(x, y, facing)` on the battlefield grid the single source
of truth, so PR-D's rules engine has reliable inputs.

**Scope:**
- Audit every read site for "where is X?" — sheet, combat_context,
  battlefield grid — and route through one canonical accessor.
- Movement ops (`move`, `5ft_step`, `withdraw`, `charge`) become
  structured backend mutations that update the grid before any
  resolver fires.
- AI-described movement (out of `Steps::CombatGm` today, out of
  `Steps::CombatRollRequest` after PR-E) parses into the same ops.
- Migration: backfill any existing battlefield rows that have stale or
  inconsistent positions.

**Ship criteria:**
- Specs prove that flanking/AoO/cover queries derive from the grid only.
- No remaining read path goes through a paragraph of AI prose to learn a
  position.

### PR-D — Rules engine: flanking, AoO, cover, reach

**Goal:** code does the rule arithmetic.

**Scope:**
- New `app/services/combat/rules.rb` (or similar) module with:
  - `Combat::Rules.flanking?(attacker, target, battlefield)`
  - `Combat::Rules.aoo_targets_for(mover, battlefield)`
  - `Combat::Rules.cover_between(attacker, target, battlefield)`
  - `Combat::Rules.reach_for(attacker)` (and `threatens?(attacker, square)`)
- Wire into PR-B's deterministic attack resolver: flanking +2, cover -4,
  AoO triggers on movement out of a threatened square (resolved before
  the move completes).

**Ship criteria:**
- Unit tests for every rule with hand-built grid scenarios.
- Integration test: a player attack against a flanked target rolls
  with +2.
- AoO from movement works for both player- and NPC-initiated moves.

### PR-E — `Steps::CombatRollRequest` for free-text in combat

**Goal:** free-text escape hatch goes through a single AI call,
inheriting deterministic state.

**Scope:**
- New step `Steps::CombatRollRequest` that mirrors the
  `Steps::RollRequest` pattern. Prompt context carries `combat_active=true`,
  attack-options text, battlefield text, `action_economy_remaining`,
  current threats/flanking facts, and RAG-retrieved combat rules
  (via `Rules::Lookup` with a combat-biased query).
- Output: the same flat JSON as out-of-combat RollRequest, but `roll`
  may be `attack_roll | saving_throw | skill_check`. For combat rolls,
  emits `attack_option_id` + `target` and **never** a `dc`.
- Adapter routes combat-domain rolls through
  `CombatMechanicResolution.normalize_player_roll` to resolve DCs
  deterministically. Same error type as today's chain so existing
  retry/error handling still applies.
- Default action cost = standard, unless the model explicitly tags
  the action as move/swift/free.
- Routing: in `AdventureLoopResolution#run_evaluation_phase`, when
  `combat_active?` and the input is free-text (not a structured action
  from the HUD), route to `CombatRollRequest`.

**Ship criteria:**
- Free-text combat actions ("I throw sand in his eyes") produce the
  expected roll, action-economy cost, and threading into Combat GM (or
  combat_narrator after PR-G) for verdict.
- Existing combat regression tests pass.

### PR-F — Bestiary `behavior_policy` + deterministic NPC turns

**Goal:** kill the per-NPC AI fan-out. This is the cost-collapse moment.

**Scope:**
- Migration: add `behavior_policy` JSON column to `creature_sheets`.
- v1 schema:
  ```json
  {
    "preferred_attacks": ["javelin@>=20ft", "longsword@melee"],
    "approach_when_out_of_reach": true,
    "morale": { "flee_at_hp_pct": 0.15 },
    "ability_triggers": []
  }
  ```
- New `Combat::NpcTurn.run!(creature, battlefield, combat_state)` that
  walks the policy: pick an action that matches the first satisfied
  `preferred_attacks` entry, approach if out of reach, check morale,
  trigger abilities, run the action through the same deterministic
  resolver as PR-B.
- Extend `Steps::CreatureGeneration` to emit a `behavior_policy` from
  the creature's existing attacks/abilities (one-time AI cost per
  creature, deterministic forever).
- Replace the AI fan-out in `world_turn/combat_advancement.rb` with a
  loop over `Combat::NpcTurn.run!`.
- Backfill task for existing bestiary entries.

**Ship criteria:**
- A 6-creature encounter completes a round with **zero NPC AI calls**.
- New creatures from `creature_generation` carry valid policies.
- Backfill rake task populates existing rows.
- Spec coverage for each policy field.

### PR-G — `combat_narrator` step

**Goal:** replace `combat_gm`'s mechanical-adjudication role with a pure
flavor narrator over a structured round log.

**Scope:**
- New step in `StepRegistry`: `combat_narrator`. Own prompt template,
  own token budget, own model knob. Default to a creative-leaning model
  with a tight token budget — output is one paragraph.
- Prompt input: structured round log (player action + NPC actions +
  hits/misses/damage/conditions applied). No mechanical adjudication
  asked of the model — that's already done.
- `Steps::CombatGm` either deletes its verdict logic and renames to
  `combat_narrator`, or stays as a thin shim that calls the new step
  and returns the narration where today it returns
  `{ outcome, mutations }`. Decide at implementation time based on
  callers.

**Ship criteria:**
- Narration paragraph reads with combat voice distinct from the default
  narrator.
- Round log → narration is a pure function (deterministic input ⇒ same
  shape of output).

### PR-H — `action_event` social-ramification hook

**Goal:** combat actions with narrative weight propagate to the right
context update without bloating the combat hot path.

**Scope:**
- Every deterministic combat `action_event` posts to a small queue.
- Heuristic gate (no AI): `location_type == "settlement" && nearby_npcs.any? &&
  action.kind in [draw_weapon, cast, equip_armor, attack_npc_civilian]`
  triggers a `social_context_update` enqueue.
- Existing `social_context_update` step processes the trigger as today —
  AI runs there, not in the gate.

**Ship criteria:**
- Drawing a weapon in a tavern with NPCs present triggers a social
  context update; drawing a weapon mid-battle does not.
- Spec coverage for the trigger heuristic.

### PR-I — Retire `Steps::ParallelEvaluation`

**Goal:** remove the legacy chain and the Node evaluator microservice if
nothing else uses it.

**Scope:**
- Delete `Steps::ParallelEvaluation`, `Phases::BeaconPhase`,
  `Phases::MechEvalPhase`, `Phases::RollQualifierPhase`,
  `EvaluatorTransport`, the legacy mech_eval prompt templates, and the
  `evaluator/` Node service if no other caller remains.
- Delete `ensure_damage_metadata_for_active_hit!` and the
  `build_mech_eval_prompts(["combat"], ...)` retry — unreachable after
  PR-E + PR-F.
- Drop the `evaluation_mode` toggle from `DmConfig` (or pin it as the
  only mode that remains, and remove the setter from the admin UI).
- StepRegistry cleanup: remove `beacon`, `mechanical_evaluation`,
  `roll_qualifier` entries.
- Update `docs/pipeline_steps.md` and `docs/pipeline_diagram.md`.

**Ship criteria:**
- Test suite passes with zero references to the deleted code.
- A staging soak confirms no regressions in either combat or
  out-of-combat for a full session.

---

## Risks worth naming up front

1. **Behavior-policy DSL is the make-or-break for NPC feel.** A bad v1
   schema will feel like a downgrade from AI-tactician NPCs. Mitigation:
   start with a single creature type in playtest before backfilling the
   whole bestiary.
2. **Free-text fidelity.** `CombatRollRequest` needs accurate
   action-economy and grid state injected to emit rolls that fit
   reality. Mitigation: PR-A and PR-C land before PR-E so the inputs
   exist before the consumer.
3. **Grid authority migration touches a lot.** PR-C is the riskiest
   single PR. Mitigation: write the canonical-position spec first, then
   migrate readers one at a time behind it.
4. **Edge cases that resist determinism.** PF1e is gnarly — condition
   stacking, environmental effects, partial cover from nuanced terrain.
   Mitigation: each edge case discovered becomes a permanent addition
   to the rules engine. We don't have to ship all of PF1e on day one;
   we have to ship enough that the common case is right.

---

## Open questions to revisit later

- **Round narration cadence:** every round, or batched (every N rounds
  for routine fights, always for boss swings)? Current decision: every
  round. Revisit if `combat_narrator` cost shows up on the meter.
- **Action-economy expressiveness in v1:** swift action slot for
  quickened spells, full-round actions, immediate actions, free actions
  cap per round. Decide as we hit the first creature/spell that needs
  them.
- **NPC behavior-policy v2:** when the v1 schema starts feeling thin,
  expand to multi-condition rules ("if flanked AND HP > 50%, 5-foot
  step then full-attack"; "use Bull's Strength turn 1, then full-attack
  thereafter").

---

## Tracking

PR sequence in the task list:
PR-A → PR-B → PR-C → PR-D → PR-E → PR-F → PR-G → PR-H → PR-I.
Each PR commits and pushes against
`feat/combat-determinism-arc` (or a child branch from it) until the arc
is merged.
