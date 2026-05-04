# AI Dungeon Master

A full-stack web application that pairs D&D-style character sheet management with an AI-powered Dungeon Master running Pathfinder 1e text adventures. Players interact through natural language; the system interprets intent, enforces game mechanics, and narrates outcomes through a multi-step pipeline that blends LLM calls with deterministic game logic.

Built with Rails 7, React/TypeScript, PostgreSQL, and the OpenAI API.

## How It Works

A player types something like *"I try to pick the lock on the chest"*. That input travels through a pipeline of ~15 steps — some powered by AI, some by plain code — before the player sees a narrated result. The pipeline can pause mid-flow to request dice rolls or initiative from the player, then resume where it left off.

### Pipeline Overview

```
Player input
  │
  ├─ Triage ──────────── Sanitize (AI) ║ Classify (AI)   ← parallel
  │
  ├─ DM Query? ──────── fast-path for out-of-character questions
  │
  ├─ Sequencer (AI) ──── splits compound actions into a queue
  │
  └─ Per action:
       │
       ├─ Evaluation (single AI call):
       │    ├─ RollRequest         ── out-of-combat: rules+beats RAG, picks one roll spec or "no roll"
       │    └─ CombatRollRequest   ── in-combat free-text: attack options + battlefield context
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
            └─ Context Update (AI) ─── persists combat_context advancement + scene_summary
```

### AI Steps

| Step | What it does |
|---|---|
| **Sanitize** | Scores input danger (0–100) and produces a cleaned version |
| **Classify** | Tags the action domain: combat, traversal, social, exploration, rest, inventory, or dm_query |
| **DM Query** | Answers out-of-character questions without running the full pipeline |
| **Sequencer** | Breaks compound actions (*"I search the room and then open the door"*) into ordered sub-actions |
| **RollRequest** | Out-of-combat single AI call. Decides whether the intent needs a die roll, emits one roll spec (or "no roll") plus the cross-cutting signals (affected_contexts, transition, combatants). Prompt has no character block — top-K rules and scene_facts retrieval (intent + current location + active combat participants), retrieved from pgvector |
| **CombatRollRequest** | In-combat free-text single AI call. Same shape as RollRequest, but the prompt carries attack options, action economy, threats, and the battlefield slice. Combat rolls emit `attack_option_id`; DCs and damage are resolved post-call from the sheet via `CombatMechanicResolution` |
| **Sanity Checker** | Capability check (sheet-based) + world consistency check (pgvector retrieval against `adventure_narrative_facts`, `adventure_npcs`, and `adventure_locations`) |
| **Mechanic** | Post-roll arbitration out of combat. Also handles no-roll auto-success outcomes — every action flows through this verdict path |
| **Combat GM** | Post-roll arbitration in combat: produces structured mutations + battlefield patches; consumes deterministic attack-roll facts assembled from the resolved `attack_option_id` |
| **Time Keeper** | Estimates how much in-game time the action took |
| **Loremaster** | Extracts new durable narrative facts from the turn's outcome and writes them to `adventure_narrative_facts`. Runs in parallel with Narrate inside Stagehand |
| **Narrate** | Generates the narrative prose the player actually reads. Reads `scene_facts` (intent-keyed) + `outcome_facts` (outcome-keyed) retrievals against the facts store |
| **Combat Narrator** | Async flavor pass after End Turn — turns the round's deterministic NPC events into one paragraph |
| **Context Update** | Persists combat-context advancement (when free-text combat is active) and the meta scene_summary |
| **ExtractFromPremise** | Authoring-time fact extraction at story save: reads `Story.premise` + `Story.opening_message`, populates `Story.seed_facts` |

### Deterministic Steps

| Step | What it does |
|---|---|
| **Mutations** | Applies HP changes, conditions, inventory updates, and other state changes to the database |
| **GameClock** | Advances the in-game clock, recalculates light conditions and fatigue thresholds |
| **Harbinger** | Checks encounter tables for random encounters based on time, location, and noise |
| **Warmaster** | Initializes combat: creates creature sheets, rolls NPC initiative, sets turn order |
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

Each AI step can be configured independently (model, token budget, on/off toggle) through `DmConfig`, an admin-editable settings object.

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
