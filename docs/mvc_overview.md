# MVC Overview

This document summarizes all Models, Views, and Controllers in the application. The project is a Rails 7+ API application with a React SPA frontend, implementing an AI-powered Dungeon Master system.

> **Project moment (2026-05):** approaching launch. The model + controller surface here is stable; the active work is on the pipeline (a GM-orchestrator step is the next major change — see `docs/design_philosophy.md` and `docs/pipeline_steps.md`). New AI steps still need a `StepRegistry` entry, but the dispatch shape that consumes them will change.

---

## Models

Located in `app/models/`. 38 model files total.

### Foundation


| Model               | Description                                                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| `ApplicationRecord` | Base class for all Active Record models                                                          |
| `User`              | Authenticated user; has many sheets, adventures, and dm_logs                                     |
| `DmConfig`          | Singleton configuration for DM settings, AI model selection, token budgets, and evaluation modes |
| `FeatureFlag`       | Runtime feature toggles for A/B testing and gradual rollouts                                     |


### Character Sheets


| Model            | Description                                                                             |
| ---------------- | --------------------------------------------------------------------------------------- |
| `Sheet`          | Player character sheet with base stats, derived stat calculations, and currency helpers |
| `AdventureSheet` | Snapshot copy of a `Sheet` scoped to a specific adventure instance                      |
| `AdventureActorSheet`  | NPC/monster stat block with creature types, attitudes, and origin tracking              |


### Sheet Join Tables

Each sheet type has its own set of join tables for feats, spells, and items:


| Model                 | Description                                                |
| --------------------- | ---------------------------------------------------------- |
| `SheetFeat`           | Links feats to a `Sheet`                                   |
| `SheetSpell`          | Links spells to a `Sheet` (known/spellbook)                |
| `SheetItem`           | Links items to a `Sheet` with slot management and quantity |
| `AdventureSheetFeat`  | Links feats to an `AdventureSheet`                         |
| `AdventureSheetSpell` | Links spells to an `AdventureSheet`                        |
| `AdventureSheetItem`  | Links items to an `AdventureSheet`                         |
| `AdventureActorSheetFeat`   | Links feats to a `AdventureActorSheet`                           |
| `AdventureActorSheetSpell`  | Links spells to a `AdventureActorSheet`                          |
| `AdventureActorSheetItem`   | Links items to a `AdventureActorSheet`                           |


### Catalog / Definitions


| Model             | Description                                                                    |
| ----------------- | ------------------------------------------------------------------------------ |
| `FeatDefinition`  | Feat catalog with categories (combat, general, metamagic, item_creation)       |
| `SpellDefinition` | Spell catalog with school, class levels, and components                        |
| `ItemDefinition`  | Equipment catalog with armor/shield bonuses, weight, cost, and slot properties |


### Adventure & Story


| Model                | Description                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------- |
| `Adventure`          | Active game session linking a user and story; carries `combat_context` + `time_context`  |
| `AdventureMessage`   | Chat/narrative messages with types: narrative, roll_request, action_result, etc.         |
| `AdventureNpc`       | Per-adventure NPC, written by `Lore::ApplyNpcs` (pgvector embedding for fuzzy lookup)    |
| `AdventureLocation`  | Per-adventure location with `(x, y)` coordinates + embedding, written by `Lore::ApplyLocations` |
| `AdventureNarrativeFact` | Per-adventure durable narrative fact with embedding; sole writer is `Lore::ApplyResults` |
| `Story`              | Quest/campaign authoring artifact: title, preview, premise, opening_message, seed_facts, world_terrain, encounter tables |
| `StoryLocation`      | Authored named location, seeded into `adventure_locations` at adventure creation         |
| `StoryNpc`           | Authored NPC, seeded into `adventure_npcs` at adventure creation                         |


### Encounters & Bestiary


| Model                 | Description                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------- |
| `EncounterTable`      | Container for a set of random encounter entries                                             |
| `EncounterTableEntry` | Single encounter possibility with weight, terrain/level filters, and optional AI generation |
| `BestiaryEntry`       | OGL/SRD Pathfinder creature template used to seed `AdventureActorSheet` instances                 |


### AI Pipeline & Logging


| Model           | Description                                                                          |
| --------------- | ------------------------------------------------------------------------------------ |
| `PipelineRegistryEntry` | Operational registry for one async run (correlation uuid, status, timing, PlayLog linkage) |
| `Pipeline`              | Domain through-line for a run; `has_many` `AdventureLoop` rows for that execution          |
| `AdventureLoop` | Persistent cross-step pipeline context; holds tags, data store, timeline, and status |
| `DmLog`         | Records Dungeon Master activity with step-level granularity                          |
| `AiLog`         | Records individual AI API calls with token counts and response status                |
| `AiUsageRecord` | Aggregates token consumption and cost per model                                      |


---

## Controllers

Located in `app/controllers/`. 23 controller files total.

### Core


| Controller               | Routes / Actions                           | Description                                                       |
| ------------------------ | ------------------------------------------ | ----------------------------------------------------------------- |
| `ApplicationController`  | (base)                                     | Authentication, policy-based authorization, `current_user` helper |
| `HomeController`         | `GET /`                                    | Redirects admins to dashboard, others to sheets list              |
| `SessionsController`     | `POST /login`, `DELETE /logout`, `GET /me` | Authentication endpoints                                          |
| `StoriesController`      | `GET /stories`                             | Returns available stories for adventure creation                  |
| `LegalController`        | `GET /privacy`, `GET /terms`               | Static legal pages                                                |
| `FeatureFlagsController` | `GET /feature_flags`                       | User-facing feature flag state                                    |


### Character Management


| Controller                   | Routes / Actions              | Description                                                                                |
| ---------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------ |
| `SheetsController`           | Full CRUD on `/sheets`        | Create/read/update/delete character sheets; syncs feats, spells, and items via join tables |
| `AdventureSheetsController`  | `PATCH /adventures/:id/sheet` | Updates feat, spell, and item selections for an adventure-scoped sheet                     |
| `FeatDefinitionsController`  | `GET /feat_definitions`       | Read-only catalog with category and parameter filtering                                    |
| `SpellDefinitionsController` | `GET /spell_definitions`      | Read-only catalog with school, class, and level filtering                                  |
| `ItemDefinitionsController`  | `GET /item_definitions`       | Read-only catalog with type and slot filtering                                             |


### Adventure Play


| Controller                    | Routes / Actions                                                    | Description                                                                                          |
| ----------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `AdventuresController`        | `POST /adventures`, `GET /adventures/:id`, `DELETE /adventures/:id` | Creates adventures (copies sheet, seeds NPCs/locations/facts from the story), shows state, deletes   |
| `AdventureMessagesController` | `POST /adventures/:id/messages`                                     | Accepts player prompts, initiative rolls, and skill checks; triggers async AI pipeline               |


### Admin Namespace (`/admin/...`)


| Controller                        | Description                                                                |
| --------------------------------- | -------------------------------------------------------------------------- |
| `AdminController`                 | Admin base controller with role guard                                      |
| `admin/DmLogsController`          | Browse and inspect DM activity logs                                        |
| `admin/AiLogsController`          | Browse AI call logs with pipeline run visualization                        |
| `admin/DmConfigsController`       | Manage DM configuration (model selection, token budgets, evaluation modes) |
| `admin/StoryController`           | Full CRUD for stories and all world-building sub-resources                 |
| `admin/AdventuresController`      | View and manage all user adventures                                        |
| `admin/BestiaryEntriesController` | Import and manage OGL creature templates                                   |
| `admin/BillingController`         | Track and visualize token usage and costs                                  |
| `admin/FeatureFlagsController`    | Enable/disable feature flags globally                                      |


---

## Views

Located in `app/views/`. The application is primarily a JSON API; HTML views are thin ERB templates that boot React SPAs or serve static content.

### Layouts


| File                           | Description                                     |
| ------------------------------ | ----------------------------------------------- |
| `layouts/application.html.erb` | Main application layout; loads React SPA assets |
| `layouts/legal.html.erb`       | Simplified layout for legal pages               |
| `layouts/mailer.html.erb`      | HTML mailer layout                              |
| `layouts/mailer.text.erb`      | Plain-text mailer layout                        |


### Feature Views


| Directory           | Description                                                |
| ------------------- | ---------------------------------------------------------- |
| `views/home/`       | Minimal redirect landing page                              |
| `views/sheets/`     | Character sheet listing and editor entry point (React SPA) |
| `views/adventures/` | Adventure creation and gameplay entry point (React SPA)    |
| `views/admin/`      | Admin dashboard views for all admin sub-controllers        |
| `views/legal/`      | Privacy policy and terms of service pages                  |
| `views/stimulus/`   | Stimulus JS integration helpers                            |


---

## Architecture Notes

- **API + SPA hybrid**: Controllers respond with JSON for API calls and render ERB shells to boot the React frontend.
- **Policy-based authorization**: All controllers use Pundit-style policy objects; `ApplicationController` enforces authorization.
- **Join table pattern**: Many-to-many relationships (feats, spells, items) are managed through explicit join-table models to support adventure-scoped snapshots.
- **AI pipeline**: `AdventureMessagesController` triggers an async multi-step pipeline (`PlayerTurn::Engine`) tracked by `PipelineRegistryEntry` (logs/admin correlation), domain `Pipeline`, and `AdventureLoop`; results are streamed back via Action Cable.
- **Entry-service boundary**: `PlayerTurn::Service` is now a compatibility facade; prompt/roll/initiative entrypoints are owned by focused deterministic services (`PlayerTurn::EntryServices::PromptExecution`, `PlayerTurn::EntryServices::ResumePipelineExecution`) with shared runtime wiring in `PlayerTurn::EntryRuntime`.
- **Singleton config**: `DmConfig` holds a single global configuration record accessed by pipeline steps for model and budget decisions.
- **Value-object construction seams**: builder-style hash assembly is being replaced with explicit constructors at boundaries (for example `Adventures::TimeContext`, `Adventures::CombatState`, `Onboarding::SheetBlueprint`, and battlefield action-economy payload objects) to keep invariants owned close to object creation.
- **Narrative state via pgvector**: durable world state lives in `adventure_narrative_facts`, `adventure_npcs`, and `adventure_locations` (each table embeds + has structured columns). The world consistency check, narrator, and encounter wiring read from these surfaces by retrieval rather than from JSONB context blobs. `combat_context` (for live combat state) and `time_context` (for the clock) survive as the only structured JSONB context fields on `Adventure`.

