# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-04-27

Shipped since **[0.1.0]** (~100 merged PRs). Grouped by theme; representative PRs cited where helpful.

### Pipeline & Dungeon Master

- **Parallel evaluator**: Beacon → mechanical evaluation → roll qualifier runs through the Node microservice (`EVALUATOR_URL`); Ruby parallel fan-out migrated off threads to Node `/fan_out` (#55, #62).
- **Structure**: Former monolithic pipeline split into `PipelineEngine` modules and phased concerns (#88, #89); large refactor series (#91–#94); follow-up cleanup epic (#98, #106).
- **Token budgets**: Remove blanket default caps so DM-configured budgets apply as written (#96).
- **Loop semantics**: `AdventureLoop#pipeline_outcome` is the authoritative narrative seed; DB assembly covered by specs (#33, #34).
- **Naming**: `PipelineRun` → **`PipelineRegistryEntry`** (`registry_entry_uuid` on play logs, adventure loops, AI usage, suggestions); **`DungeonMaster::CoreResolver`** → **`DungeonMaster::AdventureLoopResolution`** (#114, #115).
- **Evaluation**: Retire legacy “unified evaluation only” path; parallel beacon/mech chain is the supported mode (#36, #28, #60).
- **Steps**: Remove standalone intent step (#26); AI response schemas live in JSON (#27); iterative compound actions UI (#59); similarity-based dedup of roll requests (#83).
- **Moderation**: Dedicated moderation stage in pipeline (#78).
- **World sanity checker**: Optional, then defaulted off during early access (#58, #99, #104); adventure loop ids on logs (#105).

### Billing & accounts

- Stripe plans, Checkout, webhook-driven subscription sync (#103); payment options and gates (#107); plan pricing updates (#109); follow-up Stripe/Webhook fixes (#110, #111, #113).

### Retrieval, embeddings & rules

- **Narrative memory**: pgvector-backed narrative facts store for world-consistency checks (#101).
- **Cost observability**: Token usage and cost for embedding API calls (#102).
- **Rules RAG**: `rule_embeddings` + rules lookup service for retrieval-driven prompts (#116).

### Combat, encounters & rolls

- Initiative roll UI and encounter context when combat starts (#31); Harbinger post-time initiative gap (#84); combat turn control (#95).

### Character sheet & progression

- Conditions tracked in adventure (#3); skill rank-up flow (#86); class abilities (#108); inventory mutations in pipeline (#49); dynamic items embedded in sheet JSON (#51); sheet draft restoration (#112).

### Observability & infrastructure

- Play logs + pipeline telemetry shipped to **Axiom** and **S3** (#53).
- **Sentry** for staging/production (#22); preview deploy/teardown (#24); env-specific credentials (#23).
- Email delivery **SES → Resend** (#52).

### Product UI & routing

- Mobile-friendly adventure UI and navigation (#10, #13); first-time tutorials / subdomain onboarding (#64, #74).
- Landing and OAuth/subdomain fixes (#65–#72, #76); legal pages (#79); Google Analytics on front page (#80).

### Admin & tooling

- Inline adventure context editing with Playwright coverage (#14); richer pipeline debug view + log export (#30); DM config keys surfaced (#29).

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
[0.4.0]: https://github.com/Leather-Armor-IO/rpg-tools/releases/tag/v0.4.0
[0.1.0]: https://github.com/Leather-Armor-IO/rpg-tools/releases/tag/v0.1.0
