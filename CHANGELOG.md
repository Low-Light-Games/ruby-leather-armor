# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions **0.2.0–0.4.0** are documented retroactively from merged PR dates (they were not tagged at the time).

## [Unreleased]

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
