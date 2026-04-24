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
       ├─ Player Interpreter (AI) ── extracts pure mechanical intent
       │
       ├─ Beacon (AI) ───────────── per-domain interpretation (combat, social, etc.)
       │
       ├─ Mechanics gate (parallel):
       │    ├─ Mechanical Evaluation (AI) ── determines rolls, DCs, NPC actions
       │    └─ Sanity Checker (AI/code) ──── capability + world consistency
       │
       ├─ ⏸ awaiting player rolls (if needed)
       │
       ├─ Roll Qualifier (AI) ───── situational modifiers, Take 10/20
       ├─ Verdict (AI) ─────────── post-roll arbitration, structured mutations
       ├─ Mutations (code) ──────── applies HP, conditions, inventory changes
       ├─ Time Keeper (AI/code) ── time estimation → GameClock advancement
       ├─ Harbinger (code) ──────── random encounter checks
       │    └─ Warmaster (code) ── combat setup if encounter triggers
       │         └─ ⏸ awaiting initiative
       │
       └─ Output phase (parallel):
            ├─ Chronicler (AI) ──────── plot state, clue discovery, DM notes
            ├─ Narrate (AI) ─────────── prose response to the player
            └─ Context Update (AI) ──── refreshes micro/macro world state
```

### AI Steps

| Step | What it does |
|---|---|
| **Sanitize** | Scores input danger (0–100) and produces a cleaned version |
| **Classify** | Tags the action domain: combat, traversal, social, exploration, rest, inventory, or dm_query |
| **DM Query** | Answers out-of-character questions without running the full pipeline |
| **Sequencer** | Breaks compound actions (*"I search the room and then open the door"*) into ordered sub-actions |
| **Player Interpreter** | Strips flavor to extract pure mechanical intent |
| **Beacon** | Interprets the action within each relevant domain context, run in parallel per domain |
| **Mechanical Evaluation** | Determines required rolls, DCs, NPC reactions, and consequences |
| **Roll Qualifier** | Adds situational modifiers, decides Take 10/20 eligibility |
| **Sanity Checker** | Validates the action is physically/narratively possible |
| **Verdict** | Arbitrates roll outcomes and produces structured mutation instructions |
| **Time Keeper** | Estimates how much in-game time the action took |
| **Chronicler** | Tracks plot progression, discovered clues, and DM-facing notes |
| **Narrate** | Generates the narrative prose the player actually reads |
| **Context Update** | Refreshes six micro-contexts (combat, traversal, social, exploration, rest, inventory) and the macro story summary |

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
| **NPC Roll Resolution** | Rolls dice on behalf of NPCs during mechanical evaluation |
| **AdventureLoopResolution** | Resolves one AdventureLoop row: ParallelEvaluation → Sanity → Mechanic/Combat GM → TimeKeeper → optional World Turn (mixed into Pipeline) |

## Architecture

The system separates concerns into three layers:

- **DungeonMasterService** — thin entry point that persists messages, handles errors, and delegates to the pipeline.
- **DungeonMaster::PipelineEngine** — pure orchestration logic: step sequencing, branching, parallelism, and pause/resume for dice rolls.
- **Step modules** (`DungeonMaster::Steps::*`) — each step is an isolated module with its own ERB prompt template and structured output contract.

Each AI step can be configured independently (model, token budget, on/off toggle) through `DmConfig`, an admin-editable settings object.

Prompts live as ERB templates in `app/services/dungeon_master/templates/`, keeping prompt engineering separate from pipeline logic. Most domains still use the generic `mechanical_evaluation` prompt family, while `combat` now uses `combat_mechanic` plus Ruby-side normalization for live AC / save DC resolution.

Six **micro-contexts** (JSONB columns on `Adventure`) give each step a focused, domain-specific window into game state rather than dumping the full history into every prompt.

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

The automated spec suite is intentionally narrow.

- Keep request specs that verify deterministic, user-visible behavior from the HTTP boundary.
- Do not keep specs as documentation or to restate implementation details.
- If a behavior requires heavy mocking to appear testable, it is out of scope for the spec suite.
- AI-integration internals, prompt wording, and orchestration details are validated outside this suite.
