# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions **0.2.0–0.4.0** are documented retroactively from merged PR dates (they were not tagged at the time).

## [Unreleased]

### Added

- **`Steps::CastResolve` (CastResolver)** — new top-of-action AI step in the out-of-combat pipeline. Names every creature the player could plausibly target / address / evade / observe as `[{name, type, count}]` against a closed five-entry type enum (`beast`, `fighter`, `goblinoid`, `spellcaster`, `commoner`). Code resolves each entry deterministically through a four-tier lookup: existing `AdventureNpc` → existing `CreatureSheet` → `BestiaryEntry` by name (story-scoped first, then public) → `BestiaryEntry.default_for(type)`. The resulting `PlayerTurn::CastRoster` is persisted on the `AdventureLoop` (so `RollPipelineJob`'s pause/resume cycle keeps it) and rendered into the RollRequest prompt as `[id=N] Name (attitude) — at <loc>`. Replaces the entire "AI invents a creature, code tries to back-fill identity" failure surface with code-owned `creature_sheet_id` integers from the very top of the turn.
- **`Encounters::CreatureCreation.from_bestiary`** — single deterministic minting path that turns a `BestiaryEntry` (story-scoped, public, or `default_for_type`) into N `CreatureSheet` rows on an Adventure. Used by the cast resolver, the encounter bridge, and the authoring tools — every creature on every adventure flows through this one method.
- **`BestiaryEntry` flavors** — three named flavors enforced by scope: public (`story_id` null, `default_for_type` null — the SRD-style shared catalog), story-scoped (`story_id` present — named NPCs hand-statted or AI-drafted-and-human-reviewed for one story; `StoryNpc#bestiary_entry_id` always points here), and default-by-type (`default_for_type` present — the five seeded fallbacks used by `CastResolver` when the AI's `name` doesn't resolve to anything more specific). Single table, branchless minting; new flavors are a new column + scope, not a new table.
- **`Authoring::AuthorStoryNpcSheet`** — story-save-time tool that renders the `creature_generation` AI step against a `StoryNpc`, returns a draft for human review in the admin editor, and (on save) persists a `BestiaryEntry` linked to the StoryNpc. Story save now blocks on every named StoryNpc having a bestiary entry; the runtime pipeline never invokes `creature_generation`.
- **`Combat::OpposedRollResolution`** — deterministic DC resolution for opposed rolls (Stealth → Perception, Bluff → Sense Motive, Diplomacy → Sense Motive, Disguise → Perception, Sleight of Hand → Perception, Intimidate → Sense Motive, …). Resolves DC from the target sheet whenever `target_creature_sheet_id` references a creature carrying the deciding stat. Soft contract: if the AI emits a non-null `dc` for an opposed roll type, the value is overridden with the code-resolved one and the conflict is reported to Sentry as `opposed_roll_dc_conflict` so prompt-quality regressions stay visible.
- **`Steps::GameMaster` request_roll tool** — second iteration of the GM. The GM can now emit a `tool_calls: [{name: "request_roll", args: {intent_text: ...}}]` field alongside its narrative. When present, `Phases::GameMaster` validates the call via the new `Tools::Registry`, dispatches into a slim `Steps::RollRequest` variant (new `roll_request_as_tool.text.erb` prompt — no `needs_roll`, no cross-cutting signals; mechanical_summary preserved for resume-path compat), creates and binds an `AdventureLoop` with status `paused`, synthesizes an `EvaluationResult`-backed intent + a build_merged_from_result-style merged hash, and returns `:awaiting_rolls`. The lead narrative persists as a separate `narrative` AdventureMessage alongside the standard `roll_request` message — two messages per pause. Resume path is unchanged from today: `run_rolls` → `Mechanic` → `apply_mutations` → `TimeKeeper` → `Narrate`. No wrap step yet; voice inconsistency on roll-required turns is the deliberate tradeoff. Cap: 1 tool call per turn this iteration (only `request_roll` supported).
- **`Steps::GameMaster`** — first iteration of the reasoning-model orchestrator behind the `gamemaster_orchestrator` feature flag. When enabled for a user (and combat is not active), `run_prompt` branches at a new `Phases::GameMaster` after `IntakeDangerGate`, bypassing `OrchestrateCompoundActions`. The step reads the player intent + a small world envelope (location, time_context, NPCs via `Lore::NpcsLookup`, recent DM messages, full story premise) and emits the player-facing narrative directly, with `adventure_ended` / `player_dead` flags wired into the existing `Adventure.mark_ended!` path. No tools yet — `adjudicate` / `introduce_npc` / `begin_combat` land in the next iteration; this PR exists to nail placement and feature-flag gating before the tool surface arrives. Audit: one `event_type: "game_master_plan"` PlayLog row per turn carrying `{reasoning, narrative_chars, adventure_ended, player_dead}`. Seeded as `mode: "off"` in `db/seeds/feature_flags.rb`.

### Changed

- **`Authoring::` namespace** — all story-save / authoring AI tooling moved out of the runtime pipeline tree (`app/services/lore/extract_from_premise.rb`, `lore/generate_opening_message.rb`, `embedding`, `encounter_expand`, and the new `creature_generation`) into `app/services/authoring/`. `Ai::StepRegistry` marks each with `pipeline: false`; the folder name and the registry flag are redundant on purpose — they catch each other in code review. The runtime pipeline can no longer accidentally invoke an authoring step (no per-turn AI cost surprises, no unsigned stat blocks shipped under a player turn).
- **`Steps::RollRequest` contract** — removed `combat_combatants` / `normalized_combatants` (the impromptu-name-matching that mangled "Lord Velkar Mhonn" into "Velkar Mhon"). Added optional `target_creature_sheet_id` (an integer copied verbatim from the cast roster — omitted when there is no target). Kept `transition` as a separate typed signal, since combat-start is orthogonal to target identity (a hostile target can be observed / intimidated / lied to / negotiated with; a friendly target can be attacked).
- **`Steps::CombatRollRequest` contract** — same optional `target_creature_sheet_id` for in-combat free-text non-attack rolls, sourced from the live combat roster. The existing `attack_option_id` flow for the structured Combat HUD path is untouched.
- **`Encounters::Warmaster.persist_combat_from_cast_roster!`** replaces `initialize_from_names!`, `prepare_from_names!`, `spawn_from_names`, `resolve_creature`, and `create_from_ai_static`. Combatants are picked deterministically from the cast roster: the action's `target_creature_sheet_id` plus any pre-existing hostile entries; indifferent / friendly bystanders stay out of combat. No name-fuzzy-matching, no per-turn AI generation.
- **`PlayerTurn::Steps::Stagehand`** always runs the parallel narrative fan-out before the combat-init hand-off — the player gets the hit / Stealth / etc. outcome prose first, and the awaiting-initiative message rides on top of the narrative, not in lieu of it. Closes the gap that made `attack_envoy.spec.js` fail at `hitMessage` even when everything else was correct.
- **`PlayerTurn::Steps::ContextUpdate`** output contract slimmed to pure deltas. AI emits `participant_updates: [{ creature_sheet_id, hp_delta, conditions_added, conditions_removed }]` keyed by integer `creature_sheet_id` (validated against the adventure's actual sheets); unknown IDs are dropped with a `play_log!("context_update_unknown_id", …)` event. The full `participants` block is gone — code projects canonical state from the prior `combat_context` plus deterministic CombatGM mutations and applies the AI's deltas on top.
- **Story seeds (`db/seeds/envoys_gambit_story.rb` et al.)** — every named StoryNpc ships with a hand-authored `BestiaryEntry` at `db:seed` time. No AI runs at seed time; every dev gets a deterministic, free, human-signed seed.
- **FeatureFlag** is now per-user. The binary `enabled` boolean is replaced by a `mode` (`off` / `on` / `bucketed`) plus two exclusive bucketing strategies — `granular` (a list of user IDs that are ON) and `modulo` (`user.id % divisor` matches one of `on_remainders`; divisor 2–10 supports 10–90% rollouts). The legacy `FeatureFlag.enabled?(key)` global API is dropped (no callers); use `FeatureFlag.enabled_for?(key, user)`. Admin UI gets an edit page; the public `GET /feature_flags` endpoint filters by per-user evaluation. First step of the GameMaster orchestrator epic.

### Removed

- **`Encounters::Warmaster#initialize_from_names!`** and the entire impromptu-name-matching chain (`prepare_from_names!`, `spawn_from_names`, `resolve_creature`). The bug class it carried — RollRequest emitting a mangled name, Warmaster fuzzy-matching it to the wrong row or to nothing — is now structurally impossible because identity is owned by code from the moment the cast roster is built.
- **`Encounters::Warmaster.create_from_ai_static`** — the per-turn AI stat-block generator. The only remaining caller is `EncounterWarmasterBridge`, which has its own `from_bestiary` path keyed on `EncounterTableEntry#manifest`. The runtime pipeline no longer invokes the `creature_generation` AI step at all (its `Ai::StepRegistry` flag flipped to `pipeline: false`).
- **`combat_combatants` / `normalized_combatants` from `Steps::RollRequest`** — see Changed § for the replacement contract.
- **Combat narrator (PR-G)** — the end-of-round AI flavor narration step never produced visible output: `AiClient#chat` forces `response_format: {type: "json_object"}` globally, but the narrator's prompt asked for prose without the word "json", so OpenAI 400'd every call and the narrator's `rescue` block swallowed the error. Combat-end always fell through to the canned `combat_end_narration_for(reason)` system message ("Combat ends — every hostile is down. The battlefield falls quiet."). Removed `Combat::Narrator`, `Combat::Narrator::Context`, `Combat::Narrator::StepParams`, `CombatNarratorJob`, the `combat_narrator.text.erb` prompt, the `combat_narrator` `StepRegistry` entry and `COMBAT_NARRATOR` model hint, the `combat_narrator_enabled` `DmConfig` toggle and predicate, the `combat_narrator_failure` `PlayLog` event_type, and the `enqueue_combat_narrator!` call site in `Combat::Resolvers::EndPlayerTurn`. Historical PR-G section in `docs/combat_redesign.md` retained with a `[REMOVED]` marker per §14, including notes on what to fix if the narrator is reintroduced.

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
