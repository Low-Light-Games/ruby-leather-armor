# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions **0.2.0–0.4.0** are documented retroactively from merged PR dates (they were not tagged at the time).

## [Unreleased]

### Changed

- **FeatureFlag** is now per-user. The binary `enabled` boolean is replaced by a `mode` (`off` / `on` / `bucketed`) plus two exclusive bucketing strategies — `granular` (a list of user IDs that are ON) and `modulo` (`user.id % divisor` matches one of `on_remainders`; divisor 2–10 supports 10–90% rollouts). The legacy `FeatureFlag.enabled?(key)` global API is dropped (no callers); use `FeatureFlag.enabled_for?(key, user)`. Admin UI gets an edit page; the public `GET /feature_flags` endpoint filters by per-user evaluation. First step of the GameMaster orchestrator epic.

## [0.5.0] - 2026-05-04

Micro-context removal epic plus the post-epic redesign — pgvector retrieval as the world model, deterministic combat as the system of record, and traversal that actually moves the player on the map (#123).

### Changed

- **Pipeline shape**: Retired Chronicler, Momentum, Enricher, Embellisher, Social Expansion, and the per-NPC AI fan-out. ContextUpdate is combat-only; Combat GM emits the whole initiative band as one structured payload that code resolves deterministically.
- **`Adventure.current_location_id`** repointed from `story_locations` to `adventure_locations`. TimeKeeper's journey-code branch now writes the column directly: full hours granted → destination row; Harbinger interrupt → a deterministic encounter-site row created via `Adventures::EncounterSiteCreator` and `Lore::ApplyLocations` at the lerped position. Player ends up properly placed on the map either way; backfill migration ships the FK switch.
- **`combat_context.participants`** stays in sync with canonical creature/player sheets via `Combat::ContextSync.refresh_participants!` after every deterministic mutation. Previous drift caused stale rosters across rounds.
- **Default model** for every AI step is now `gpt-5-nano` at `reasoning_effort: minimal` (overrides intact via `step_models` / `step_reasoning_efforts`).
- **GM grounding**: DM Query, RollRequest, and CombatRollRequest receive `SceneRetrieval::ForResolution` — facts + nearby locations (with miles + bearing relative to current_location) + known NPCs. Closes the "approximately three miles north" hallucination class.
- **`Loremaster`** prompt rewritten around post-resolution tense — facts describe what is now true after this turn, not action-mid-flight.
- **`Story.opening_message`** is now required; pre-validation stories get a JIT generation via `Lore::GenerateOpeningMessage` driven by `Lore::ExtractFromPremise`'s sibling pattern.

### Added

- **Combat log persistence**: `Combat::EventLog` writes a player-visible `combat_log` AdventureMessage at every deterministic resolution seam (Attack, Move + AoOs, Buff, Heal, NpcTurn events) and at combat-start (`PersistCombatStart` writes "Combat begins. Initiative — …"). The HUD path is no longer silent in the chat.
- **Encounter sites** as first-class `adventure_locations` rows so the player can keep playing from where the encounter actually happened.
- **`SceneRetrieval`**: Composer + `Retrieval` value object + bearing helper + a partial that renders ESTABLISHED FACTS / NEARBY LOCATIONS / KNOWN NPCS into prompts.

### Removed

- Five non-combat micro-context JSONB columns (`traversal_context`, `social_context`, `exploration_context`, `rest_context`, `inventory_context`) and the steps that wrote them.
- `affected_contexts` / `affected_domains` / `domain_results` keys throughout (output, intent, loop metadata, prompts, schemas).
- Dead Story columns (`initial_summary`, `initial_contexts`) and Adventure columns (`enriched_world`, `enriched_premise`, `plot_state`).
- `StoryClue`, `StoryMilestone`, and the related UI surface.
- StoryNpc `'enricher'` / `'embellisher'` source values; collapsed to `manual`.
- StepRegistry entries for `npc_action`, `enricher`, `embellisher`.
- Stale `guardrail_mode` toggle from docs and admin UI.

### Fixed

- **Traversal**: `update_player_position!` runs after every TimeKeeper journey, so "I run to the keep" advances time *and* moves the player.
- **Destination resolver**: matches both polluted long-form ("Garrison Keep (7.07 miles southwest) or…") and short-form ("keep") destinations against `adventure_locations` via two-pass substring containment.
- **DM Config admin page**: removed dead `authoring-tools-toggle` JS that crashed the script and silently broke every later wiring on the page.

---

## [0.4.0] - 2026-04-27

Commerce, retrieval layers, and registry/naming consistency — roughly PRs merged **2026-04-19** onward.

### Changed

- **`PipelineRun` → `PipelineRegistryEntry`** (`registry_entry_uuid` across play logs, loops, usage, suggestions); **`DungeonMaster::CoreResolver` → `DungeonMaster::AdventureLoopResolution`**; pipeline regression hardening (#114, #115).
- **World sanity checker**: Defaults off broadly; noop path + adventure loop ids on related logs (#99, #104, #105).
- **Epic codebase cleanup** after the refactor wave (#98, #106).

### Added

- **Combat**: Improved combat turn control (#95).
- **Retrieval**: Narrative facts store (**pgvector**) for world-consistency checks (#101); **rules RAG** (`rule_embeddings`, lookup service) (#116).
- **Costs**: Token usage and dollar cost for embedding API calls (#102).
- **Billing**: Stripe plans, Checkout, webhook subscription sync (#103); payment gates and pricing iterations (#107, #109); Stripe/Webhook follow-ups (#110, #111, #113).
- **Characters**: Class abilities (#108); sheet draft restoration (#112).

---

## [0.3.0] - 2026-04-17

Subdomains, pipeline decomposition, and deep refactors — roughly **2026-03-29** through **2026-04-18**.

### Added

- **Routing & onboarding**: Landing CTA; subdomain/OAuth/admin boundary fixes (#65–#72, #76); wizard tutorial (#74); moderation stage (#78); legal (#79); Google Analytics (#80).
- **Combat & encounters**: Harbinger/initiative gap fix (#84); skill rank-ups (#86); UI polish (#85); stat tooltip clipping (#87).
- **Rolls**: Similarity-based deduplication of roll requests (#83); accumulated intents initialization (#81); auto-success filter correction (#82).

### Changed

- **Pipeline**: God-class decomposition and phased modules (#88, #89).
- **Refactor series**: Value objects & concerns (#91); stats calculator split (#92); DungeonMaster splits (#93); services/presenters/query objects (#94).
- **DM config**: Remove opaque default caps on step token budgets (#96).
- **Policies**: Adventure policy updates (#97).

---

## [0.2.0] - 2026-03-27

Evaluator stack, observability, and launch-hardening — roughly **2026-03-19** through **2026-03-27**.

### Added

- **Parallel evaluation**: Beacon → mech eval → roll qualifier via **Node** (`EVALUATOR_URL`); Ruby parallel calls moved off threads to Node **`/fan_out`** (#55, #62).
- **Pipeline UX**: Async pipeline with live progress (#37); richer pipeline debug view + export (#30); iterative rolls (#4); iterative compound-actions UI (#59).
- **Loop semantics**: `AdventureLoop#pipeline_outcome` as authoritative narrative seed + specs (#33, #34).
- **Observability**: Play logs + pipeline telemetry to **Axiom** + **S3** (#53); clearer pipeline error logging (#32).
- **Ops**: Preview deploy/teardown (#24); env-specific credentials (#23); **Sentry** staging/production (#22); outbound mail **SES → Resend** (#52).
- **Product**: Public landing (#1); AI-facing copy moved into templates (#2); mobile adventure UI (#10, #13); conditions in play (#3); embellisher-generated opening DM line (#40); first-time tutorial / app subdomain groundwork (#64).
- **Combat UI**: Initiative roll UI and encounter context when combat starts (#31).
- **Admin**: Inline adventure context editing with Playwright (#14); remaining DM config keys surfaced (#29).

### Changed

- **ContextUpdate**: Ownership/coverage refactor (#35).
- **Evaluation path**: Unified beacon/mech as default (#28); unified-only mode (#36); retired legacy unified-eval naming (#60).
- **Steps**: Removed standalone intent step (#26); AI response schemas in JSON (#27).
- **Economy / sheets**: Raised token budgets + truncate logging (#42); retired edge pipeline (#43); inventory mutations (#49); saving-throw mapping (#48); sheet save regression (#47); embedded item defs in sheet JSON (#51); Postgres volume path for prod (#50).
- **Prompts**: Narrate/sequencer tuning (#56); consistency checker wording (#41); seed stories toward test scenarios (#38).
- **Sanity**: World sanity checker optional (#58).

### Fixed

- Google OAuth login on repeated attempts (#9, #12).

---

## [0.1.0] - 2026-03-18

First live deployment to leatherarmor.io. Marks the end of local-only development
and the start of the app's public life.

### Added

**Core adventure system**
- Story and adventure domain: create stories with premise, context, and initial summary
- Adventure play UI with optimistic messages, thinking indicator, and retry support
- Soft-deletable adventures
- In-game clock display
- Concentration check button for spellcasters
- dm_query mode for explicit player-to-DM communication
- Directed play style toggle

**AI pipeline**
- Async step-based pipeline via Sidekiq + ActionCable
- Steps: Sanitize, Classify, Intent, Sequencer, CoreResolver, MechanicalEvaluation, Ruling, Chronicler, Evaluate, Momentum, RollQualifier
- Configurable model selection per step in DM configs
- Pipeline profiling: PipelineRun model with per-step timing
- Retry on transient errors
- StepRegistry as single source of truth for step metadata
- Unified evaluation mode option in DM configs

**Character sheets**
- Feat and spell definitions stored in DB with effects and prerequisites
- Server-side derived stats engine
- Item definitions with full equipment stats
- Point-buy stat allocation
- In-adventure equip/unequip functionality
- Base equipment and starting currency support

**Combat**
- Encounter-to-combat lifecycle with creature manifests and initiative flow
- Encounter tables with story-specific locations
- Dynamic damage roll UI

**World / story tools**
- Story locations, NPCs, clues, and milestones
- Story enrichment system
- Traversal context seeded from starting location
- Time-span journey resolver
- NPC social scene expansion

**Admin**
- Adventure dashboard with edit capabilities and pipeline debug links
- Token usage and billing dashboard
- Feature flags with toggle UI
- DM config editor with per-step model selection

**Infrastructure**
- Production Dockerfile with gated asset precompilation (dev builds skip it)
- `docker-compose.prod.yml` for EC2 deployment
- GitHub Actions deploy workflow: SSH → pull → build → migrate
- Reference data (feats, spells, items, bestiary, encounter tables, The Lake of Whispers story) promoted from seeds to data migrations
- Version logged on every production log line and at startup
- `.env` managed via GitHub environment secrets; never committed

### Fixed
- Puma double-bind on port 3000 (removed redundant `port` directive and `plugin :tmp_restart`)
- Stale social context on location change
- Phantom journey encounters
- Missing message types in adventure pipeline
- Silent AI fallbacks replaced with loud failures in dev / graceful degradation in prod

[Unreleased]: https://github.com/Leather-Armor-IO/rpg-tools/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/Leather-Armor-IO/rpg-tools/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Leather-Armor-IO/rpg-tools/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Leather-Armor-IO/rpg-tools/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Leather-Armor-IO/rpg-tools/releases/tag/v0.1.0
