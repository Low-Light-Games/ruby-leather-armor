# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/matheuscosta/app/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/matheuscosta/app/releases/tag/v0.1.0
