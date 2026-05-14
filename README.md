# AI Dungeon Master

A full-stack web application that pairs D&D-style character sheet management with an AI-powered Dungeon Master running Pathfinder 1e text adventures. Players interact through natural language; the system interprets intent, enforces game mechanics, and narrates outcomes through a multi-step pipeline that blends LLM calls with deterministic game logic.

Built with Rails 7, React/TypeScript, PostgreSQL, and the OpenAI API.

## Project status (2026-05)

Approaching launch. The architecture has converged: deterministic combat as the system of record, pgvector-backed durable world state, single-call evaluation (RollRequest / CombatRollRequest), async-only pipeline. The exploratory phase is over — the codebase is consolidating around what worked.

**Current direction:** a **GM-orchestrator** step is the next major change. Capable reasoning models will own more of the chain of thought directly, with the existing pipeline steps refactored into scoped specialist tools the orchestrator delegates to (sheet handler, roll referee, time keeper, loremaster, etc.). The cheap-non-reasoning-model bet that motivated the original decomposition didn't deliver the nuance social encounters and narrative-driven combat transitions need; the pivot is documented in `docs/design_philosophy.md` (§3 and §10 are marked `[OUTDATED]` with the pivot story preserved). The pipeline diagram below describes the current behavior — the orchestrator hasn't shipped yet.

## How It Works

A player types something like *"I try to pick the lock on the chest"*. That input travels through a pipeline of ~15 steps — some powered by AI, some by plain code — before the player sees a narrated result. The pipeline can pause mid-flow to request dice rolls or initiative from the player, then resume where it left off.

### Pipeline Overview

```
Player input
  │
  ├─ Intake (AI) ─────── sanitizes input and scores danger (0–100)
  │
  ├─ Sequencer (AI) ──── splits compound actions into a queue
  │
  └─ Per action:
       │
       ├─ CastResolver (AI, out-of-combat only):
       │      names every creature the action could touch and resolves each
       │      one to a real `actor_sheet_id` via the four-tier lookup
       │      (existing AdventureNpc → existing AdventureActorSheet → BestiaryEntry
       │      by name → BestiaryEntry by `default_for_type`). Output is a
       │      cast roster of integer IDs that downstream steps reference
       │      directly — no name strings on the wire.
       │
       ├─ Evaluation (single AI call):
       │    ├─ RollRequest         ── out-of-combat: rules+beats RAG + cast roster, picks one roll spec or "no roll"; emits optional `target_actor_sheet_id` (an id from the roster) and orthogonal `transition` signal
       │    └─ CombatRollRequest   ── in-combat free-text: attack options + battlefield context + live participant ids
       │
       ├─ Sanity Checker (AI/code) ── capability + world consistency
       │
       ├─ ⏸ awaiting player rolls (if needed)
       │
       ├─ Verdict (AI):
       │    ├─ Mechanic            ── post-roll arbitration out of combat
       │    └─ Combat GM           ── post-roll arbitration in combat (verdict step only)
       │
       ├─ Mutations (code) ──────── applies HP, conditions, inventory changes
       ├─ Time Keeper (AI/code) ── time estimation → GameClock advancement
       ├─ Harbinger (code) ──────── random encounter checks
       │    └─ Warmaster (code) ── combat setup if encounter triggers
       │         └─ ⏸ awaiting initiative
       │
       ├─ Combat HUD path (deterministic, when player uses the action panel):
       │    ├─ Combat::PlayerActionResolver ── attack / move / end-turn (server-side dice + clamping)
       │    └─ Combat::NpcTurn               ── per-NPC engine off behavior_policy (no AI calls)
       │
       └─ Output phase (parallel fan-out at Stagehand):
            ├─ Narrate (AI) ────────── prose response, fed by scene_facts + outcome_facts retrieval
            ├─ Loremaster (AI) ─────── extracts new durable facts from the turn's outcome
            └─ Context Update (AI) ─── persists combat_context advancement (combat-only)
```

### AI Steps

| Step | What it does |
|---|---|
| **Intake** | Single AI call at the top of every turn: sanitizes the player input and scores its real-world danger (0–100). The earlier separate `Sanitize` and `Classify` steps were folded into Intake; action-domain classification was retired entirely with the micro-context cleanup |
| **Sequencer** | Breaks compound actions (*"I search the room and then open the door"*) into ordered sub-actions |
| **CastResolver** | Out-of-combat single AI call at the top of every action. Names every creature the player could plausibly interact with (target / address / evade / observe) as `[{name, type, count}]` against a closed five-entry type enum (`beast`, `fighter`, `goblinoid`, `spellcaster`, `commoner`). Code resolves each entry deterministically through the four-tier lookup and persists the cast roster on the `AdventureLoop` so RollRequest, Stagehand, and the resume path all see the same integer `actor_sheet_id`s. Cheapest reasoning model — same tier as RollRequest |
| **RollRequest** | Out-of-combat single AI call. Decides whether the intent needs a die roll, emits one roll spec (or "no roll"), and — when the action targets a single creature — copies that creature's `actor_sheet_id` from the cast roster into `target_actor_sheet_id` (omitted when there is no target). The orthogonal `transition` signal indicates combat-start. Prompt has no character block — top-K rules + cast roster + scene_facts retrieval, all from pgvector |
| **CombatRollRequest** | In-combat free-text single AI call. Same shape as RollRequest, but the prompt carries attack options, action economy, threats, and the battlefield slice. Combat rolls emit `attack_option_id`; DCs and damage are resolved post-call from the sheet via `CombatMechanicResolution`. Free-text rolls share the same optional `target_actor_sheet_id` contract as RollRequest, sourced from the live combat roster |
| **Sanity Checker** | Capability check (sheet-based) + world consistency check (pgvector retrieval against `adventure_narrative_facts`, `adventure_npcs`, and `adventure_locations`) |
| **Mechanic** | Post-roll arbitration out of combat. Also handles no-roll auto-success outcomes — every action flows through this verdict path |
| **Combat GM** | Post-roll arbitration in combat: produces structured mutations + battlefield patches; consumes deterministic attack-roll facts assembled from the resolved `attack_option_id` |
| **Time Keeper** | Estimates how much in-game time the action took |
| **Loremaster** | Extracts new durable narrative facts from the turn's outcome and writes them to `adventure_narrative_facts`. Runs in parallel with Narrate inside Stagehand |
| **Narrate** | Generates the narrative prose the player actually reads. Reads `scene_facts` (intent-keyed) + `outcome_facts` (outcome-keyed) retrievals against the facts store |
| **Combat Narrator** | Async flavor pass after End Turn — turns the round's deterministic NPC events into one paragraph |
| **Context Update** | Persists combat-context advancement when free-text combat is active. The retired scene_summary subsystem is gone — battlefield init seeds its scene note from the last few player-facing AdventureMessages (`Battlefield::PersistCombatStart#recent_scene_note`) |
| **ExtractFromPremise** | Authoring-time fact extraction at story save: reads `Story.premise` + `Story.opening_message`, populates `Story.seed_facts` |

### Deterministic Steps

| Step | What it does |
|---|---|
| **Mutations** | Applies HP changes, conditions, inventory updates, and other state changes to the database |
| **GameClock** | Advances the in-game clock, recalculates light conditions and fatigue thresholds |
| **Harbinger** | Checks encounter tables for random encounters based on time, location, and noise |
| **Warmaster** | Initializes combat from the cast roster: combatants are the action's `target_actor_sheet_id` plus any pre-existing hostile roster entries (indifferent / friendly bystanders stay out). Rolls NPC initiative, sets turn order, persists the pending combat context. No name-fuzzy-matching, no per-turn AI generation — every participant is a real `actor_sheet_id` minted by the `CastResolver` upstream |
| **ActorSheetCreation** | `Encounters::ActorSheetCreation.from_bestiary` — the single deterministic path that turns a `BestiaryEntry` (story-scoped, public, or `default_for_type`) into N `AdventureActorSheet` rows on an Adventure. Used by the cast resolver, the encounter bridge, and the authoring tools |
| **CombatMechanicResolution** | Normalizes combat mech-eval JSON into authoritative attack/save DCs from live sheet data |
| **World Turn** | Resolves post-player NPC turns in active combat, advances turn/round state, and short-circuits on combat end |
| **Stagehand** | Orchestrates the final output shape — decides what gets sent back to the player |
| **Combat::PlayerActionResolver** | Server-authoritative attack / move / end-turn for the deterministic Combat HUD |
| **Combat::NpcTurn** | Per-NPC turn engine driven by `behavior_policy` JSONB (preferred attacks, approach, morale flee) — no AI call per NPC |
| **AdventureLoopResolution** | Resolves one AdventureLoop row: RollRequest or CombatRollRequest → Sanity → Mechanic/Combat GM → TimeKeeper → optional World Turn (mixed into Pipeline). No-roll actions flow through the same path with auto-success |
| **Maps::PlaceLocations** | Vogel-spiral coordinate placement at story save; deterministic per `story_id`. Distance between any two locations is euclidean × `Adventure.coordinate_scale` × per-terrain speed factor |
| **EncounterWarmasterBridge** | Reads hostile NPCs at the current location from `adventure_npcs` to merge pre-established scene enemies into encounter rosters |
| **Combat::SocialEventTrigger** | Reads non-hostile witnesses at the current location from `adventure_npcs` for social-weight combat events |

## Architecture

The system separates concerns into three layers:

- **DungeonMasterService** — thin entry point that persists messages, handles errors, and delegates to the pipeline.
- **DungeonMaster::PipelineEngine** — pure orchestration logic: step sequencing, branching, parallelism, and pause/resume for dice rolls.
- **Step modules** (`DungeonMaster::Steps::*`) — each step is an isolated module with its own ERB prompt template and structured output contract.

Runtime DM behavior (thresholds, pacing, toggles) is configured through
`DmConfig`. Per-step model routing is versioned in
`config/dm_step_models.yml` and resolved at runtime via
`DmConfig#model_for`.

Prompts live as ERB templates in `app/services/dungeon_master/templates/`, keeping prompt engineering separate from pipeline logic. The single-call evaluation step (`roll_request` out of combat, `combat_roll_request` in combat) carries no character block; combat rolls emit an `attack_option_id` and DC/damage resolution happens post-call in Ruby via `CombatMechanicResolution`.

Durable world state lives in three pgvector-backed stores rather than JSONB context blobs: `adventure_narrative_facts`, `adventure_npcs`, and `adventure_locations`. Each combines structured columns with an embedding so consumers (sanity check, narrator, encounter bridge) can mix structured filters with similarity retrieval. Only `combat_context` (live combat state) and `time_context` (the clock) survive as structured JSONB context fields.

## Tech Stack

| Layer | Technologies |
|---|---|
| Backend | Ruby 3.3.1, Rails 7.1.6, PostgreSQL 16, Puma |
| Frontend | React 18, TypeScript, esbuild, Sass |
| AI | OpenAI API with per-step model selection |
| Async | Sidekiq, Redis, ActionCable |
| Infrastructure | Docker, Docker Compose, Traefik |

## Getting Started

```bash
docker compose up
docker compose exec app bin/rails db:create db:migrate db:seed
```

The app is accessible at `http://exercises.localhost`. Traefik dashboard at `http://localhost:8080`.

For local development without Docker: `bundle install && yarn install && bin/dev`.

## Documentation

The `docs/` folder contains detailed design documents for the pipeline, individual steps, utilities, and architectural decisions. This README is an abridged overview — refer to the docs for implementation specifics.

## Engineering Signals

- **AI for judgment, code for certainty**: AI decides intent, narrative, and ambiguous rulings; code resolves deterministic mechanics from authoritative state.
- **Keep AI contracts small**: ask for the minimum decision needed (`needs_roll?`, target selection, option id), then derive DCs, damage, and bounds in code.
- **Receiving seam translates to canonical state**: AI output can be near-correct in shape; receiving code normalizes and clamps before persistence.
- **Code is self-documenting; comments are exceptions**: prefer clear names and small boundaries. When boundary docs are needed, use concise YARD contract tags (`@param`, `@return`, hash shape).

## Testing Philosophy

The automated spec suite is intentionally narrow. Most regression coverage
comes from end-to-end Playwright tests in `test/e2e/`, not from RSpec.

**Prefer a single multi-turn Playwright e2e over many small unit specs**
for any flow that exercises the HTTP boundary, the React HUD, and the
database round-trip together — combat encounters, sheet edits, inventory
toggles, sidebar refreshes. One e2e that drives the real product through
several coupled actions catches more regressions, with less drift, than
twenty unit specs each pinning one resolver method's hash shape.

**RSpec is reserved for** request specs that verify a deterministic
response at the HTTP boundary, and for pure utilities whose public
contract IS the thing under test (parsers, validators, value objects with
non-trivial logic). If a unit's only consumer is one e2e away, delete the
unit spec and let the e2e own the coverage.

**Anti-patterns we've removed:**

- Specs that exist to "document" what the code does. Code is the
  documentation; specs are regression nets.
- Specs that re-state implementation details (which methods get called
  in which order, internal hash key names). They break on every
  refactor without catching real bugs.
- Specs that require mocking out three collaborators to make one
  assertion. The unit's contract is too coupled to test in isolation —
  cover it from the e2e instead.
- AI-step internals, prompt wording, and pipeline orchestration. These
  are validated outside this suite (admin play log review, manual
  playtest, evaluator runs).

**When deleting unit specs in favor of an e2e:** the e2e must explicitly
assert the same observable behavior. Run the new e2e, then revert the
production fix and re-run — if it still passes, the e2e isn't actually
covering the regression and you owe a stronger assertion before
shipping. (We caught a sidebar-doesn't-refresh-after-buff bug exactly
this way: the e2e was added without the AC-stat assertion, missed it,
then was strengthened to assert AC bumps after the cast.)
