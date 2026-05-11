# Micro-Context Removal Epic — Implementation Plan

Single-PR epic that removes the five non-combat micro-context domains,
replaces them with structured stores keyed off pgvector, retires the
Chronicler / clue / milestone scaffolding, and repoints every consumer
to the new surfaces. Commits are ordered so each one leaves the repo
in a working state. The PR is reviewed and merged as one unit; commit
separation is for reviewer ergonomics.

## Why

The five non-combat micro-contexts (`traversal_context`, `social_context`,
`exploration_context`, `rest_context`, `inventory_context`) were designed
under the assumption that cheaper models could each own a domain via
focused, narrow prompts. That hasn't panned out. The ContextUpdate step
is the sole writer of these JSONB columns, and the value the columns
deliver downstream — scene awareness for Narrate, structured anchors for
EncounterWarmasterBridge, world-state for AdventureLoopResolution sub-steps
— is now better served by a smaller, more focused set of structured
stores plus retrieval against the existing `adventure_narrative_facts`
pgvector table.

`combat_context` is kept (it carries short-lived, structurally
load-bearing state — `participants`, `turn_order`, `battlefield_ref`,
`action_economy` — that can't be reconstructed from prose). `time_context`
is kept (it's the higher-order, code-managed clock state, separate from
the narrative six).

Chronicler is retired alongside the contexts. Clue-discovery and
milestone-arbitration were the deterministic plot scaffolding the
Chronicler enforced; those judgements are subjective and should emerge
from play, not be flagged from a fixed authoring structure.

## Architectural decisions made

These were resolved iteratively during planning. The plan below assumes
all of these.

1. **Five non-combat micro-context columns are removed.** `combat_context`
   and `time_context` stay.
2. **NPCs get a dedicated pgvector store (`adventure_npcs`)** with
   structured columns (name, location, attitude, etc.) plus an embedding
   for fuzzy lookup. `StoryNpc` is seeded into the new store at adventure
   creation. `StoryNpc` itself stays in this epic; eventual removal in
   favor of free-form seeding is a future epic.
3. **Locations get a dedicated pgvector store (`adventure_locations`)**
   with `(x, y)` float coordinates plus an embedding. Location-to-location
   distance is euclidean × `Adventure.coordinate_scale` ×
   per-terrain speed factor.
4. **The world has one global terrain per Story** (`Story.world_terrain`).
   No grid cells, no procedural generation, no roads, no varied terrain
   along journeys. The "richer map" follow-up is on a separate Trello
   card. The win in this epic is dynamic distance calculation, not
   terrain variation.
5. **Location placement is deterministic Vogel-spiral layout** seeded by
   `story_id`. The generator fully decides positions; `StoryLocation`
   does not gain an `(x, y)` hint column.
6. **`LocationConnection` is removed.** Coordinates plus uniform world
   terrain replace authored connections. `StoryLocation` keeps `name` and
   `description`, drops distance/connection-related fields.
7. **Chronicler is removed.** `StoryClue`, `StoryMilestone`, and their
   admin UI / `AdventureMessage` types are deleted. No clue-to-fact
   migration; legacy data is discarded under the "no users yet" rule.
8. **Story slims to `{ title, preview, premise, opening_message,
   seed_facts, encounter_tables }`.** Field-by-field, including
   reconciliation with the existing schema:
   - `title` — unchanged.
   - `preview` — keep the existing column. Player-safe storefront copy
     used by story-listing UI. No rename in this epic; if a rename to
     `description` is preferred later, that's a small follow-up.
   - `premise` — repurposed (no schema change, only semantic change).
     Becomes the **spoiler-bearing** author document. Never shown to
     the player. AI extracts facts from this at story save into
     `seed_facts`.
   - `opening_message` — **new column** (added in Commit 2). Author-
     written prose rendered as the player's first `AdventureMessage`
     of type `narrative` at adventure creation. Player-safe by
     definition (it's the live opening scene).
   - `seed_facts` — **new column** (added in Commit 2). AI-extracted
     from premise + opening_message at story save; reviewable in the
     editor before publish; bulk-inserted into `adventure_narrative_facts`
     at adventure creation (deterministic, no AI call at spin-up time).
   - `encounter_tables` — unchanged (the association/table itself).

   **Schema cleanup of fields not in the slimmed shape** (Commit 2's
   migration):
   - `initial_summary` — drop. Subsumed by `opening_message`.
   - Any other Story columns not listed above — audit-pass during
     Commit 2; drop or note explicitly. (Likely candidates to
     verify: `world_premise`, `style_directives`, `tone`, etc., if
     any of those exist.)

   No `visibility` tagging on facts — all facts are equal, and retrieval
   relevance is the firewall. If retrieval surfaces a spoiler, the
   Narrator may use it; that's the accepted trade-off.
9. **DM Brief mechanism is gone.** Narrator does not read
   `Story.premise` directly (premise is spoiler-bearing). Narrator's
   world-orientation comes from `scene_facts` retrieval against
   `adventure_narrative_facts`, which already contains the
   premise-extracted seed facts plus everything the player has
   established through play. Loremaster's seed prompt is fully
   deleted (Decision 18); turn prompt loses `contexts_text`.
10. **Shared `scene_facts` retrieval at the top of
    `AdventureLoopResolution`**, keyed on intent + active combat
    participants + current location name. Sub-steps (RollRequest,
    CombatRollRequest, Mechanic, Combat GM, SanityChecker, DM Query)
    read this shared input rather than running their own queries.
11. **Narrate gets a second outcome-keyed retrieval inside Stagehand**,
    keyed on `what_happened`. Narrate's input is `scene_facts +
    outcome_facts + what_happened + combat_context (when active)`.
    **Narrate does not read `Story.premise` directly** — premise is
    spoiler-bearing post-Decision 8, so its content reaches Narrate
    only through the retrieved facts (the bulk-inserted seed_facts
    were AI-extracted from premise at story save). The retrieved
    facts ARE the narrator's world orientation; there is no separate
    "story baseline" input. The Stagehand fan-out shape (Narrate
    parallel with Loremaster) is unchanged.
12. **`ContextUpdate` survives, drastically slimmed.** Combat state
    advancement updater + `scene_summary` meta output. Drops the five
    domain updaters, drops `clues_to_reveal`, drops `context_wishes`.
13. **Combat free-text path (Combat GM verdict) is preserved.** The
    AI-driven combat-state updater remains the source of truth for
    `combat_context` writes during free-text combat.
14. **Migration strategy: truncate dynamic-state tables.** No real users.
    Same migration drops columns, drops dead tables, and truncates
    `adventures`, `adventure_messages`, `adventure_sheets` + joins,
    `adventure_loops`, `pipelines`, `pipeline_registry_entries`, `dm_logs`,
    `ai_logs`, `adventure_narrative_facts`. A defensive nil-check at
    pipeline entry points swallows in-flight Sidekiq jobs without Sentry
    spam.
15. **`Steps::Momentum` is retired.** No-roll actions are run through the
    same verdict path as rolled actions: `RollRequest`'s "no roll
    needed" branch emits a synthetic auto-success outcome that flows
    through `Mechanic`, producing structured `what_happened` + mutations
    exactly as for a rolled outcome. The world moves forward through one
    machinery, not two. The split between "needs adjudication" and
    "needs narration only" was coupling two concerns — collapsing them
    eliminates a whole code path.
16. **`Enricher` and `Embellisher` are retired entirely.** Both produce
    `initial_contexts` (dying) plus, in Embellisher's case, the opening
    narrative for new adventures. The opening narrative is now an
    authored field (`Story.opening_message`); adventure creation copies
    that field into the first `AdventureMessage` of type `narrative`.
    No AI call at adventure creation. The `embellisher_mode` and any
    related DmConfig knobs are removed.
17. **AI fact extractor lands in this epic as `Lore::ExtractFromPremise`
    (or similarly named).** The "migration AI tool" Trello follow-up is
    promoted into this epic as the always-on extractor — there is no
    migration; this is just the new authoring path.
    - **At story save**, the extractor runs against
      `Story.premise` and `Story.opening_message` in one prompt,
      producing a single coherent `seed_facts` list. The prompt
      instructs the model to treat `opening_message` as describing the
      live present moment of the adventure, so when its claims conflict
      with premise the opening's facts **invalidate** the conflicting
      premise facts (using the existing `Lore::FactsChangeSet`
      `facts` + `invalidates` mechanism — same pattern Loremaster uses
      at runtime). Output is a single fact list with invalidation
      metadata where applicable.
    - The editor's `seed_facts` review surface displays the result as
      a diff: invalidated facts struck through, replacements
      highlighted. Author can edit any fact, add facts, delete facts,
      or accept as-is. No "contradictions banner", no save-blocking
      — just normal fact lifecycle made visible.
    - **At adventure creation**, no AI call: bulk-insert
      `Story.seed_facts` (already coherent post-extraction) into
      `adventure_narrative_facts`, render `Story.opening_message` as
      the first `AdventureMessage`, and proceed. Deterministic and
      cheap.
    - The on-demand "Extract Facts" button in the editor lets authors
      re-run extraction without saving (useful while iterating on
      premise prose).

18. **Vector retrieval logging covers all three surfaces with resolved
    strings.** Every vector retrieval (facts, NPCs, locations) emits
    AiLog payloads that include the resolved entity content alongside
    id and similarity score, not id+score alone. Today's facts-only
    log shows `fact_id` + confidence; the new shape adds `fact_text`,
    `npc_name` + `attitude` + `location_name`, and `location_name` +
    `(x, y)` respectively, so admins can replay a retrieval without
    joining tables manually. This applies to:
    - The existing `Lore::FactsLookup` (or current name) — enriched in
      Commit 4 when first touched.
    - New `Lore::NpcsLookup` — introduced in Commit 4 for
      SanityChecker's NPC-existence vector query.
    - New `Lore::LocationsLookup` — introduced in Commit 4 for
      SanityChecker's location-existence vector query.
    All three emit a uniform log shape so the admin UI can render them
    with one component. Per §8, audit-everything: a retrieval log that
    requires a manual join to be readable is not actually auditable.

19. **DM Brief plumbing teardown is explicit.** "Remove Chronicler" is
    not a single-step deletion. `dm_brief` and `forbidden_elements`
    references are threaded through `PipelineContext`,
    `pipeline_engine#resolve_plot`, the DM Query branch
    (`pipeline_engine/phases/dm_query_branch.rb`), and the narration
    assemblies (`narrative/narrate_prompt_view.rb`,
    `narrative/single_action_assembly.rb`,
    `narrative/accumulated_assembly.rb`,
    `narrative/narration_phase_inputs.rb`). Each of these is named in
    the relevant commit; the deletion is not implicit.

## Commit-by-commit plan

Each commit leaves the repo green (specs pass, dev server boots). Tests
update inside the commit that introduces the change.

**Commit map:**
1. `adventure_npcs` store + writer + StoryNpc seeding (dark)
2. `adventure_locations` store + Vogel-spiral placement + `world_terrain` (dark)
3. Repoint NPC-store consumers (EncounterWarmasterBridge,
   Combat::SocialEventTrigger) + TimeKeeper; drop LocationConnection
4. Shared `scene_facts` retrieval + sub-step prompt rewires + Momentum
   retirement (auto-success path)
5. Stagehand outcome retrieval + Narrate / Loremaster prompt rewires +
   narration-assembly DM Brief teardown
6. Slim ContextUpdate; remove Chronicler step + remaining DM Brief
   plumbing teardown
7. Retire Enricher and Embellisher; introduce `Lore::ExtractFromPremise`;
   rewire story save (premise + opening_message → seed_facts) and
   adventure creation (no AI call; opening_message → first
   AdventureMessage)
8. Delete clues + milestones + AdventureMessage clue types
9. Frontend + admin cleanup; dead DmConfig knobs; story strong-params
10. Schema migration + truncate + Sentry-grace
11. Documentation updates

---

### Commit 1 — `adventure_npcs` store + writer + StoryNpc seeding

**Adds the new NPC pgvector surface. Dark — no consumer reads it yet.**

- New migration: `adventure_npcs` table.
  - Columns: `id`, `adventure_id` (fk), `story_npc_id` (nullable fk for
    seed-derived rows), `name`, `description`, `attitude`
    (string/enum), `location_name` (denormalized for filtering),
    `source` (string, e.g. `'seed'` or `'runtime'`), `embedding`
    (pgvector), `last_seen_loop_id` (nullable fk), `created_at`,
    `updated_at`. Partial unique index for idempotent reapply on
    `(adventure_id, name)` where `source = 'seed'`.
- New model: `AdventureNpc`.
- New service: `Lore::ApplyNpcs` — sole writer for `adventure_npcs`.
  Same Sentry-or-die error contract as `Lore::ApplyResults`.
- Extend `Lore::SeedFromAdventure` to seed `StoryNpc` rows into
  `adventure_npcs` at adventure creation alongside the existing facts seed.
- Tests for `Lore::ApplyNpcs` (writer behavior, idempotent reapply,
  Sentry on failure) and seeding.

**Files (rough):** `db/migrate/*_create_adventure_npcs.rb`,
`app/models/adventure_npc.rb`,
`app/services/dungeon_master/lore/apply_npcs.rb`,
`app/services/dungeon_master/lore/seed_from_adventure.rb`,
`spec/services/dungeon_master/lore/apply_npcs_spec.rb`.

---

### Commit 2 — `adventure_locations` store + Vogel-spiral placement + world_terrain

**Adds coordinate-based location surface. Dark — no consumer reads it yet.**

- New migration: `adventure_locations` table.
  - Columns: `id`, `adventure_id` (fk), `story_location_id` (nullable fk),
    `name`, `description`, `x` (float), `y` (float),
    `source` (string, e.g. `'seed'` or `'runtime'`), `embedding`
    (pgvector), `created_at`, `updated_at`. Partial unique index for
    idempotent reapply on `(adventure_id, name)` where `source = 'seed'`.
- New migration: adds `Story.world_terrain` (string/enum, default
  `:plains`), `Story.seed_facts` (jsonb array, default `[]`),
  `Story.opening_message` (text, default `''`), and
  `Adventure.coordinate_scale` (float, default `1.0`, configurable).
  **Same migration drops `Story.initial_summary`** (subsumed by
  `opening_message`) and audit-passes for any other Story columns not
  in the slimmed shape per Decision 8 — drop or document each. The
  existing `Story.preview` column is kept as-is (no rename to
  `description`).
  `seed_facts` carries the AI-extracted fact list (populated by
  `Lore::ExtractFromPremise` at story save in Commit 7) that
  `Lore::SeedFromAdventure` bulk-inserts into
  `adventure_narrative_facts` at adventure creation.
  `opening_message` is the player-facing first scene rendered as the
  first `AdventureMessage` of type `narrative` at adventure creation.
  `Story.premise` itself is being repurposed (not migrated here) from
  player-safe prose to spoiler-bearing author document — see Decision
  8 and Commit 7.
- New model: `AdventureLocation`.
- New service: `Lore::ApplyLocations` — sole writer for the new table.
- New service: `Maps::PlaceLocations` — Vogel-spiral placement algorithm,
  ~10 lines, seeded by `story_id`. Returns `(x, y)` for each
  `StoryLocation`. Pure function, no side effects.
- Extend `Lore::SeedFromAdventure` to seed `StoryLocation` rows into
  `adventure_locations` using `Maps::PlaceLocations` for coordinates.
- Tests for placement determinism, writer behavior, seeding.

**Files (rough):** `db/migrate/*_create_adventure_locations.rb`,
`db/migrate/*_add_world_terrain_and_coordinate_scale.rb`,
`app/models/adventure_location.rb`,
`app/models/story.rb` (add `world_terrain`),
`app/models/adventure.rb` (add `coordinate_scale`),
`app/services/dungeon_master/lore/apply_locations.rb`,
`app/services/dungeon_master/maps/place_locations.rb`,
`spec/services/dungeon_master/maps/place_locations_spec.rb`.

---

### Commit 3 — Repoint NPC-store consumers + TimeKeeper; drop LocationConnection

**First consumer move. Three consumers come off the old surface, then the
old surface is deleted.**

- Update `EncounterWarmasterBridge` to read hostile NPCs from
  `adventure_npcs` filtered by current `location_name` and `attitude`,
  instead of `traversal_context["nearby_npcs"]`.
- Update `Combat::SocialEventTrigger` to read witnesses from
  `adventure_npcs` filtered by current `location_name` (any attitude),
  instead of `adventure.social_context`.
- Update `TimeKeeper` journey math to:
  `euclidean(loc_a, loc_b) * coordinate_scale * world_terrain_speed_factor`.
  Drop the `LocationConnection.terrain` lookup path.
- DmConfig already exposes terrain speed factors; add `:plains` default
  if missing.
- Drop `LocationConnection` model + migration to drop the table.
- Drop distance/connection-related columns on `StoryLocation` (audit
  pass: `distance_*`, any connection FK).
- Update specs: `EncounterWarmasterBridge`, `Combat::SocialEventTrigger`,
  `TimeKeeper`, any `LocationConnection` factories or fixtures.

**Files (rough):** `app/services/dungeon_master/steps/encounter_warmaster_bridge.rb`,
`app/services/combat/social_event_trigger.rb`,
`app/services/dungeon_master/steps/time_keeper.rb`,
`db/migrate/*_drop_location_connections.rb`,
`db/migrate/*_drop_distance_fields_from_story_locations.rb`,
`app/models/story_location.rb`, deleted `app/models/location_connection.rb`,
related specs.

---

### Commit 4 — Shared `scene_facts` retrieval + sub-step prompt rewires + Momentum retirement

**Repoint the AdventureLoopResolution sub-steps to read the shared
retrieval instead of context blocks. Collapse the no-roll path into the
verdict path.**

- New utility: `SceneFacts::ForResolution` — composes the retrieval key
  (intent + active combat participants + current location name), runs
  one top-K query against `adventure_narrative_facts`, returns the
  retrieved facts.
- **Retrieval lookup utilities and log enrichment (Decision 18):**
  - Enrich the existing `Lore::FactsLookup` (or the current
    facts-retrieval utility — verify name during implementation) so
    its log emission captures the resolved `fact_text` alongside
    `fact_id` and similarity score. The retrieval log payload should
    be a uniform shape: `{ kind: 'facts', hits: [{ id, score, text }, ...] }`.
  - Add `Lore::NpcsLookup` — new utility for vector queries against
    `adventure_npcs`. Used by SanityChecker's NPC-existence check
    when the player references an NPC by partial/inexact name.
    Emits log payload: `{ kind: 'npcs', hits: [{ id, score, name,
    attitude, location_name }, ...] }`.
  - Add `Lore::LocationsLookup` — new utility for vector queries
    against `adventure_locations`. Used by SanityChecker's
    location-existence check. Emits log payload: `{ kind: 'locations',
    hits: [{ id, score, name, x, y }, ...] }`.
  - All three log payloads share the `{ kind, hits: [...] }` shape so
    the admin UI (Commit 9) can render them with one component.
- Update `AdventureLoopResolution` to invoke `SceneFacts::ForResolution`
  at the top of resolve and pipe the result into each sub-step's prompt
  context.
- **Momentum retirement:** Drop the `run_momentum` branch from
  `AdventureLoopResolution`. Update `RollRequest`'s "no roll needed"
  path to emit a synthetic auto-success outcome (e.g., `{ kind:
  "auto_success", reason: "no roll required" }`) that flows through
  `Mechanic` exactly as a rolled outcome would. `Mechanic` produces
  `what_happened` + mutations for the auto-success case via the same
  prompt + structured output contract; the prompt may need a small
  branch to handle "the player succeeded; describe outcome" framing.
  Delete `app/services/dungeon_master/steps/momentum.rb` and its
  templates. Remove Momentum from `step_registry.rb` and from
  `pipeline_messenger.rb` if referenced.
- Update prompt templates / Ruby builders for:
  - `RollRequest` — drop context blocks, add `scene_facts`. Add the
    auto-success emission for no-roll cases.
  - `CombatRollRequest` — drop context blocks, add `scene_facts`. Keep
    `combat_context` reads.
  - `Mechanic` (out-of-combat verdict) — drop context blocks, add
    `scene_facts`. Handle auto-success outcomes uniformly.
  - `Combat GM` (in-combat verdict) — drop context blocks, add
    `scene_facts`. Keep combat-specific reads.
  - `SanityChecker` — capability check unchanged. World check already
    reads facts (Decision 37); add NPC retrieval slice via
    `Lore::NpcsLookup` and a location-existence retrieval slice via
    `Lore::LocationsLookup` so existence/identity checks work for
    both NPCs and locations the player may reference.
  - `DM Query` — drop context blocks, add `scene_facts`. Note: this
    step also currently reads `dm_brief` from `PipelineContext`
    (`dm_query_branch.rb`); that read is removed here as part of the
    DM Brief teardown.
- Update specs for any prompt-building paths affected; delete Momentum
  specs.

**Files (rough):** `app/services/dungeon_master/scene_facts/for_resolution.rb`,
`app/services/dungeon_master/adventure_loop_resolution.rb`,
deleted `app/services/dungeon_master/steps/momentum.rb`,
deleted `app/services/dungeon_master/templates/momentum*.text.erb`,
`app/services/dungeon_master/step_registry.rb`,
`app/services/dungeon_master/pipeline_engine/phases/dm_query_branch.rb`,
existing facts-retrieval utility (verify name; likely
`app/services/dungeon_master/lore/facts_lookup.rb`),
new `app/services/dungeon_master/lore/npcs_lookup.rb`,
new `app/services/dungeon_master/lore/locations_lookup.rb`,
prompt templates under `app/services/dungeon_master/templates/`,
related specs.

---

### Commit 5 — Stagehand outcome retrieval + Narrate / Loremaster prompt rewires + narration-assembly DM Brief teardown

**Repoint the output phase (still parallel fan-out) to the new inputs.
Strip `dm_brief` / `forbidden_elements` from the narration assembly
seam.**

- New utility: `SceneFacts::ForOutcome` — keys on `what_happened`, runs
  top-K against `adventure_narrative_facts`, returns retrieved facts.
- Update `Stagehand` to invoke `SceneFacts::ForOutcome` before building
  the Narrate prompt; pass the result as `outcome_facts`.
- Update `Narrate` prompt:
  - Drop DM Brief reference.
  - Drop the five context blocks.
  - Drop any direct `Story.premise` read (premise is spoiler-bearing
    per Decision 8; its content reaches Narrate only through the
    retrieved facts).
  - Read `scene_facts`, `outcome_facts`, `what_happened`,
    `combat_context` (when combat is active). The retrieved facts
    are the only world-orientation input.
- **DM Brief plumbing teardown (narration assembly seam):**
  - `narrative/narrate_prompt_view.rb` — drop `dm_brief` /
    `forbidden_elements` reads and any related accessors.
  - `narrative/single_action_assembly.rb` — drop dm_brief plumbing.
  - `narrative/accumulated_assembly.rb` — drop dm_brief plumbing.
  - `narrative/narration_phase_inputs.rb` — drop `dm_brief` and
    `forbidden_elements` from the input contract.
- Update Loremaster turn prompt: drop `contexts_text` parameter and
  template references.
- Update Loremaster seed prompt: drop `clues_text`, `npcs_text`,
  `locations_text`, `initial_contexts_text` parameters and template
  references.
- **Update `Lore::SeedFromAdventure`** (the only live caller of
  `render_seed_prompt`):
  - Drop the four dead positional/keyword arguments to
    `render_seed_prompt`.
  - Drop the `initial_contexts_text` builder method on the service.
  - Drop the `SeedPresenters::Npcs`, `SeedPresenters::Clues`,
    `SeedPresenters::Locations` invocations and delete the presenter
    files entirely (they're tied to dying anchors).
  - Bulk-insert `Story.seed_facts` (column added in Commit 2) into
    `adventure_narrative_facts` via `Lore::ApplyResults.call(facts:
    story.seed_facts, source: 'seed')`.
  - **Retire the seed-time Loremaster AI call entirely.** With authored
    `Story.seed_facts` bulk-inserted, the AI call's marginal value
    (implied facts beyond what the author wrote) is not worth one AI
    call per adventure creation. Delete `Steps::Loremaster.render_seed_prompt`
    and the `loremaster_seed*.text.erb` template(s) — `Lore::SeedFromAdventure`
    no longer needs to render any seed prompt. Loremaster's *turn*
    prompt path stays.
- Update specs for Narrate, Loremaster, Stagehand fan-out wiring, the
  narration-assembly classes, and `Lore::SeedFromAdventure`. Delete
  specs for removed seed presenters.

**Files (rough):** `app/services/dungeon_master/scene_facts/for_outcome.rb`,
`app/services/dungeon_master/steps/stagehand.rb`,
`app/services/dungeon_master/steps/loremaster.rb`,
`app/services/dungeon_master/lore/seed_from_adventure.rb`,
deleted `app/services/dungeon_master/seed_presenters/npcs.rb`,
deleted `app/services/dungeon_master/seed_presenters/clues.rb`,
deleted `app/services/dungeon_master/seed_presenters/locations.rb`,
`app/services/dungeon_master/narrative/narrate_prompt_view.rb`,
`app/services/dungeon_master/narrative/single_action_assembly.rb`,
`app/services/dungeon_master/narrative/accumulated_assembly.rb`,
`app/services/dungeon_master/narrative/narration_phase_inputs.rb`,
`app/services/dungeon_master/templates/narrate.text.erb`,
`app/services/dungeon_master/templates/loremaster_*.text.erb`,
related specs.

---

### Commit 6 — Slim ContextUpdate; remove Chronicler step + remaining DM Brief plumbing teardown

**Output phase shrinks. ContextUpdate keeps its narrow combat job.
Chronicler and the rest of the DM Brief plumbing come out together.**

- Update `ContextUpdate`:
  - Drop the five non-combat domain updater prompts.
  - Drop schemas for the five domains under
    `templates/schemas/contexts/*.json`.
  - Drop `clues_to_reveal` and `context_wishes` from the meta updater.
  - Keep `combat_state_advancement` deep-merge logic and `scene_summary`
    output.
  - Drop `snapshot_contexts_to_loop` writes for the five domains; keep
    `combat_context` and `time_context` in the snapshot.
- Update `Contextable::CONTEXT_FIELDS` to `[combat_context, time_context]`.
- Update `PromptHelpers::CONTEXT_FIELDS` (drop the five domains; keep
  combat-only or remove entirely if no longer used).
- Remove `Chronicler` step from `PipelineEngine`'s output phase
  fan-out. Delete the step file and its templates.
- **DM Brief plumbing teardown (engine + context seam):**
  - `pipeline_engine.rb` — remove `resolve_plot` invocation and any
    Chronicler-driven plot-data gates.
  - `pipeline_context.rb` — drop `dm_brief` / `forbidden_elements`
    accessors and any plot-data fields populated by Chronicler.
  - `pipeline_engine/concerns/entry_points.rb` — verify no orphan
    Chronicler / dm_brief references remain.
- Update specs: any pipeline engine specs covering the output phase
  shape, ContextUpdate specs, deleted Chronicler specs.

**Files (rough):** `app/services/dungeon_master/steps/context_update.rb`,
deleted `app/services/dungeon_master/steps/chronicler.rb`,
deleted `app/services/dungeon_master/templates/chronicler*.text.erb`,
deleted `app/services/dungeon_master/templates/micro_context_domain_update.text.erb`,
deleted `app/services/dungeon_master/templates/schemas/contexts/{traversal,social,exploration,rest,inventory}_context.json`,
`app/models/concerns/contextable.rb`,
`app/services/dungeon_master/prompt_helpers.rb`,
`app/services/dungeon_master/pipeline_engine.rb`,
`app/services/dungeon_master/pipeline_context.rb`,
`app/services/dungeon_master/pipeline_engine/concerns/entry_points.rb`,
related specs.

---

### Commit 7 — Retire Enricher and Embellisher; introduce `Lore::ExtractFromPremise`; rewire story save and adventure creation

**Adventure creation no longer runs any AI calls. The new authoring
model lands: `premise` is spoiler-bearing prose; `opening_message` is
the player's first scene; `seed_facts` is AI-extracted from premise +
opening_message at story save with author-time contradiction
resolution. This commit owns the entire Enricher/Embellisher surface
plus the new fact extractor, so it stays green on its own.**

- Delete `app/services/dungeon_master/enricher.rb` and its template(s).
- Delete `app/services/dungeon_master/embellisher.rb` and its template(s).
- **Remove `Admin::StoriesController#enrich`** — drop the action method,
  its `before_action :set_story` inclusion of `:enrich`, and the route
  in `config/routes.rb` (`POST /admin/stories/:id/enrich`).
- **Remove the Enrich Story frontend surface:**
  - `app/javascript/components/AdminStoryEditor/useStoryEditorState.ts`
    — drop `enriching` state, `setEnriching`, the `enrichStory`
    callback (~line 265+), and the `markedOldEnricher` reconciliation
    logic.
  - Drop the Enrich Story button component (wherever it's rendered —
    likely in the editor's header or sticky action bar).
  - Strip the "Use Enrich Story" copy from the section hint props in
    `InitialContextsSection.tsx`, `NpcsSection.tsx`, `CluesSection.tsx`,
    `MilestonesSection.tsx`. The section files themselves are deleted
    or further trimmed in Commits 8/9; this commit just makes the
    Enrich Story affordance disappear.
- **Add `Lore::ExtractFromPremise`** — new service, the always-on AI
  fact extractor.
  - Inputs: `Story.premise` (spoiler-bearing prose) and
    `Story.opening_message` (player-facing prose), passed in one
    prompt.
  - Output: a single coherent `seed_facts` list using the existing
    `Lore::FactsChangeSet` shape (`facts` + `invalidates`). The prompt
    instructs the model to treat `opening_message` as describing the
    live present moment, so its claims invalidate any conflicting
    premise-derived facts. No separate "contradictions" output.
  - Sentry-or-die error contract; deterministic JSON schema; runs
    against the model tier configured via DmConfig.
- **Wire `Lore::ExtractFromPremise` into story save:**
  - Update `Admin::StoriesController#update` and `#create` so that on
    save, the extractor runs against the saved `premise` +
    `opening_message`. Persist the resulting `seed_facts` to
    `Story.seed_facts` (carrying the invalidation metadata so the
    review surface can render the diff).
- **Add an "Extract Facts" button to the story editor** for on-demand
  re-extraction without saving (so authors can iterate on premise
  prose and see fact deltas before committing).
- **Editor UI changes:**
  - New `opening_message` textarea field (clearly labeled — "Opening
    message: the first prose the player will see when they start this
    adventure").
  - `premise` field gets a clarifying label/help text — "Spoiler-bearing
    author document. The player never sees this directly. AI extracts
    facts from it for the world model."
  - New `seed_facts` review section — displays the AI-extracted fact
    list as a diff: facts invalidated by opening_message struck through,
    their replacements highlighted. Author can edit, delete, or add
    facts manually. No "resolve before save" gate — invalidations are
    just shown, like a normal fact lifecycle.
- Update `Adventures::Bootstrap`:
  - Drop the `invokes embellisher` step.
  - Drop any Enricher invocation if present.
  - At adventure creation, copy `Story.opening_message` into the first
    `AdventureMessage` of type `narrative` so the player sees the
    opening scene immediately. **No AI call.**
- Update `Adventures::ContextInitializer`:
  - Drop initial_contexts proposal logic for the five non-combat
    domains.
  - Keep `combat_context` / `time_context` initialization (the latter
    already runs deterministic defaults via `GameClock`).
  - If the entire service becomes a no-op after the dying-context
    cleanup, delete it and call `time_context` initialization directly
    from `Adventures::Bootstrap`.
- Drop the `embellisher_mode` DmConfig knob and any Enricher-related
  DmConfig fields.
- Cross-reference: the Section *bodies* (initial-context fields, clue
  rows, milestone rows) are removed in later commits. This commit
  removes only the Enrich Story affordance and copy referring to it.
- Update specs: deleted Enricher / Embellisher specs; deleted
  `Admin::StoriesController#enrich` spec; Bootstrap spec reflects the
  new opening-narrative seam; ContextInitializer spec reflects the
  slimmed shape (or is deleted alongside the service); frontend tests
  for the editor's Enrich state (if any) deleted.

**Files (rough):** deleted `app/services/dungeon_master/enricher.rb`,
deleted `app/services/dungeon_master/embellisher.rb`,
deleted `app/services/dungeon_master/templates/enricher*.text.erb`,
deleted `app/services/dungeon_master/templates/embellisher*.text.erb`,
new `app/services/dungeon_master/lore/extract_from_premise.rb`,
new `app/services/dungeon_master/templates/lore_extract_from_premise.text.erb`,
new `app/services/dungeon_master/templates/schemas/lore/extract_from_premise.json`,
`app/controllers/admin/stories_controller.rb`,
`config/routes.rb`,
`app/javascript/components/AdminStoryEditor/useStoryEditorState.ts`,
new editor sub-components for `OpeningMessageField`, `SeedFactsReview`
(renders fact diff with invalidations),
new "Extract Facts" button component,
`app/javascript/components/AdminStoryEditor/sections/{InitialContexts,Npcs,Clues,Milestones}Section.tsx`
(hint copy only),
the Enrich Story button component file (locate via grep),
`app/services/adventures/bootstrap.rb`,
`app/services/adventures/context_initializer.rb` (slimmed or deleted),
`app/services/dungeon_master/lore/seed_from_adventure.rb` (verify it
reads `Story.seed_facts` for bulk insert as wired in Commit 5),
`app/models/dm_config.rb`,
related specs.

**Sub-decision flagged for revisit during implementation:**
- The on-demand "Extract Facts" button may become noise if extraction
  always runs on save; if so, delete the button and rely solely on
  save-triggered extraction.

---

### Commit 8 — Delete clues + milestones + AdventureMessage clue types

**All clue/milestone surface area gone.**

- Drop migration: `story_clues`, `story_milestones`, any join tables
  (`adventure_clues`, `adventure_milestones` if they exist).
- Delete models: `StoryClue`, `StoryMilestone`, related join models.
- Delete admin UI sections under `app/javascript/components/AdminStoryEditor/`
  for clues and milestones.
- Delete admin controller routes / actions under
  `app/controllers/admin/story_controller.rb` (or wherever) for clues
  and milestones.
- Audit `AdventureMessage` types — drop any clue-discovery types.
- Audit `AdventureLoop` tags — drop `clue_discovered`, `milestone_reached`
  if present.
- Delete related specs and seed-file references.
- Update `app/javascript/types.tsx` to drop clue/milestone interfaces.

**Files (rough):** `db/migrate/*_drop_story_clues_and_milestones.rb`,
deleted `app/models/story_clue.rb`, `app/models/story_milestone.rb`,
deleted `app/javascript/components/AdminStoryEditor/Clues*`,
deleted `app/javascript/components/AdminStoryEditor/Milestones*`,
`app/controllers/admin/story_controller.rb`,
`app/javascript/types.tsx`, related specs and fixtures.

---

### Commit 9 — Frontend + admin cleanup; dead DmConfig knobs; story strong-params; AiLog vector-retrieval UI

**Strip the player-app and admin-UI surface for the dying contexts.**

- Update `app/javascript/types.tsx`: drop `traversal_context`,
  `social_context`, `exploration_context`, `rest_context`,
  `inventory_context` from the `Adventure` interface.
- Update `app/javascript/components/AdventurePlay/AdventurePlay.tsx`:
  drop context props passed to subcomponents; delete any
  context-display debug subcomponents that become unused.
- Update `app/javascript/components/AdminStoryEditor/`: drop
  `initial_contexts` builders for the five domains. Keep combat seed if
  it exists, otherwise delete entirely.
- Update `Admin::AdventuresController`: scope `CONTEXT_FIELDS` to
  `[combat_context, time_context]` (or remove the editor entirely if
  combat-context editing isn't needed). Drop the spec
  `spec/requests/admin/adventure_context_spec.rb` or scope its single
  test to `combat_context`.
- DmConfig knob audit pass: remove any settings that referenced now-dead
  steps or contexts. Likely candidates (verify before removing):
  - `embellisher_mode` — already removed in Commit 7; verify no orphan
    references.
  - `directed_dm` — verify what it controls; remove if Chronicler-tied.
  - Any other knobs tied to dying steps / contexts.
- Update `Admin::StoriesController` strong params:
  - Drop `story_clues` / `clue_*` permitted attributes.
  - Drop `story_milestones` / `milestone_*` permitted attributes.
  - Drop `initial_contexts` and any context-domain permitted
    attributes.
  - Drop `location_connections` permitted attributes.
- Drop `db/seeds/{traversal,social,exploration,rest,inventory}_story.rb`
  if present, or strip their context blocks.
- Verify no orphan references in `Adventures::Bootstrap` after Commit 7
  changes.
- **AiLog admin UI: render resolved strings for vector retrievals.**
  Today the AiLog detail view shows fact id + similarity score for
  each retrieval hit. Update the view to render the enriched payload
  (Decision 18) for all three retrieval kinds:
  - **Facts** — show the resolved `fact_text` excerpt alongside
    `fact_id` and score.
  - **NPCs** — show `name`, `attitude`, `location_name` alongside
    `npc_id` and score.
  - **Locations** — show `name` and `(x, y)` alongside `location_id`
    and score.
  - Render with one shared component keyed on the `kind` field
    (`facts`, `npcs`, `locations`) per Decision 18's uniform payload
    shape.
  - Apply the change to wherever AiLog hits are surfaced (admin
    AiLog detail view, pipeline run timeline, any DM Brief/play log
    debug screens that reference retrieval hits).

**Files (rough):** `app/javascript/types.tsx`,
`app/javascript/components/AdventurePlay/AdventurePlay.tsx`,
`app/javascript/components/AdminStoryEditor/*`,
`app/controllers/admin/adventures_controller.rb`,
`app/controllers/admin/stories_controller.rb`,
admin AiLog detail view (locate the existing template/component;
likely `app/views/admin/ai_logs/show.html.erb` and/or a React
component for the retrieval-hits panel),
new shared retrieval-hits renderer component keyed on `kind`,
`db/seeds/*_story.rb`,
`app/models/dm_config.rb`,
related specs.

---

### Commit 10 — Schema migration + truncate + Sentry-grace

**Drop the columns and tables. Same migration truncates dynamic-state
tables (no users; nothing to preserve).**

- Migration: drop `traversal_context`, `social_context`,
  `exploration_context`, `rest_context`, `inventory_context` columns
  from `adventures`.
- In the same migration: truncate `adventures`, `adventure_messages`,
  `adventure_sheets` (+ join tables), `adventure_loops`, `pipelines`,
  `pipeline_registry_entries`, `dm_logs`, `ai_logs`,
  `adventure_narrative_facts`.
- Defensive nil-check at pipeline entry points
  (`PromptExecution`, `ResumePipelineExecution`,
  any `AdventureLoopJob` perform method): if
  `Adventure.find_by(id:)` returns nil, log an info-level event
  (`pipeline_post_truncate_skip`) and notify Sentry with a fixed
  `fingerprint: ['pipeline_post_truncate_skip']` so all occurrences
  collapse into a single Sentry issue (Sentry-native grouping, no
  dropped events). Real errors with different fingerprints stay
  separate. Exit clean. Not raised as a real error class.
- Update `Contextable::CONTEXT_FIELDS` to drop the five (already done in
  Commit 6, but verify column drops are consistent).
- Update specs that assumed five context columns existed.

**Files (rough):** `db/migrate/*_drop_micro_context_columns_and_truncate.rb`,
`app/services/dungeon_master/entry_services/prompt_execution.rb`,
`app/services/dungeon_master/entry_services/resume_pipeline_execution.rb`,
`app/jobs/adventure_loop_job.rb` (or wherever),
`app/models/concerns/contextable.rb`, related specs.

---

### Commit 11 — Documentation updates

**The "why" doesn't drift.**

- `docs/design_philosophy.md`:
  - §7 (Immersion preservation) — DM Brief reference removed.
  - §11 (Prompt isolation) — Unified Evaluation paragraph rewritten;
    the deliberate-exception paragraph narrows to combat-only.
  - §17 (Don't code-fix AI problems) — clue-discovery example replaced
    or removed.
  - §18 (Micro-contexts as adventure state checkpoints) — rewritten to
    cover only `combat_context` + `time_context`. Single-writer scope
    shrinks. Narrative facts store remains documented.
- `docs/pipeline_steps.md`:
  - Chronicler step entry removed.
  - Clue-discovery and milestone references removed.
  - ContextUpdate entry rewritten to reflect the slimmed shape.
  - New entries for `Lore::ApplyNpcs`, `Lore::ApplyLocations`,
    `Maps::PlaceLocations`.
  - Decision log entry summarizing this epic.
- `docs/mvc_overview.md`:
  - Drop `StoryClue`, `StoryMilestone`, `LocationConnection` from model
    table.
  - Add `AdventureNpc`, `AdventureLocation`.
  - Update controller/admin sections.
- `README.md`:
  - Pipeline diagram: remove Chronicler from output phase.
  - Step tables: drop Chronicler row, update ContextUpdate description.
  - Note that `combat_context` is the only surviving narrative context;
    `time_context` is the higher-order code-managed clock.

**Files:** `docs/design_philosophy.md`, `docs/pipeline_steps.md`,
`docs/mvc_overview.md`, `README.md`, `CHANGELOG.md`.

---

## What is explicitly NOT changed

To prevent scope creep during implementation:

- `combat_context` — preserved in full. Single-writer rules unchanged.
- `time_context` — untouched. `TimeKeeper` and `GameClock` keep their
  current shapes; only journey terrain math changes (commit 3).
- Combat HUD path (`Combat::PlayerActionResolver`, `Combat::NpcTurn`) —
  untouched.
- Combat GM verdict path (free-text mid-combat) — untouched. AI-driven
  combat-state updater stays as the source of truth for free-text combat.
- Stagehand fan-out shape (Narrate parallel with Loremaster) — preserved.
  Only the prompts inside change.
- `Lore::ApplyResults` and the existing `adventure_narrative_facts` table —
  preserved. Extended to NPCs and locations via parallel writers
  (`ApplyNpcs`, `ApplyLocations`), not replaced.
- Sheet system (`Sheet`, `AdventureSheet`, `AdventureActorSheet`, all join
  tables) — untouched.
- `EncounterTable` and `EncounterTableEntry` — untouched.
- Per-step DmConfig model selection mechanism — untouched.
- `BestiaryEntry` — untouched.
- `StoryNpc`, `StoryLocation` (the models themselves) — kept as authored
  anchors. Only `StoryLocation`'s distance/connection columns drop.
- Sidekiq / ActionCable / async pipeline shape — untouched.

## Migration / deploy

- No real users; no in-flight production data to preserve.
- Same migration drops columns and truncates dynamic-state tables.
- Sidekiq queue paused or drained during deploy. Defensive nil-check at
  pipeline entry points handles any race.
- Existing `Story` rows survive structurally. Authors with
  spoiler-bearing premises get a warning surface (or hand-clean). Story
  re-save runs `Maps::PlaceLocations` and seeds the new stores.

## Risks / watch-items

- **Narrative quality regression in Narrate.** The DM Brief gave the
  narrator a curated, focused view. Now it reads only retrieved facts
  + outcome — no direct premise read (Decision 11). Watch staging for
  prose flatness, off-tone responses, or factual drift.
- **Sparse seed_facts producing flat early-adventure prose.** Narrate
  no longer has a baseline "story document" input — its world
  orientation is entirely retrieval-driven. If `Story.seed_facts`
  is thin (an under-authored story or an extractor pass that produced
  few facts), early-turn retrievals may come back with little
  material and the narrator's prose will read generic. Mitigation is
  authoring discipline (premise + opening_message rich enough that
  the extractor produces dense seed_facts) plus the editor's
  seed_facts review surface (author can spot a thin list and add
  manually). Architectural fix is not warranted here; this is a
  content-quality watch-item.
- **Retrieval relevance drift.** Shared `scene_facts` keyed on
  intent + combatants + location may be too broad for some sub-steps.
  If a sub-step's prompts start producing noisy outputs, that's a signal
  to either narrow the key or grant the sub-step a secondary retrieval
  (per-step retrieval, option B from the planning thread).
- **Spoiler leakage in Narrate.** Without the DM Brief firewall,
  authored "world truth" facts retrieved by topical similarity may leak.
  This is the accepted trade-off; revisit only if leakage shows up
  systematically in playtests.
- **NPC location drift.** The new `adventure_npcs` store carries
  `location_name` as a string for filtering. NPC location updates are
  now an explicit write — verify that scene transitions update NPC
  locations rather than letting them go stale.
- **Embedding cost per turn.** Two pgvector queries per turn (shared
  scene_facts + outcome retrieval) plus the NPC slice in sanity check.
  Negligible at small N; flag if usage scales.
- **Mechanic cost shift for auto-success turns.** Momentum was likely
  configured on a cheaper model tier than Mechanic (post-roll
  arbitration). After Decision 15, every no-roll turn pays Mechanic's
  costs. Watch staging for per-turn token/latency growth on no-roll
  flows. Mitigation if it bites: per-step DmConfig already supports
  per-step model selection; introduce an auto-success sub-mode in
  Mechanic that picks a cheaper model when the verdict is purely
  narrative (no roll math). Treat as a follow-up only if measurements
  warrant.

## Test strategy

Per the README's testing philosophy, RSpec is reserved for HTTP-boundary
request specs and pure utilities; **most regression coverage comes from
Playwright e2e tests in `test/e2e/`.** Each commit's "specs" line above
covers the unit/request layer; the e2e layer needs explicit coverage
across the epic. Each affected e2e gets either an update inside its
nearest commit or, where the flow is wholly new, a new e2e file added
in the relevant commit.

**Existing e2e tests to update (located in `test/e2e/`):**
- **Combat encounter flow** — verify `EncounterWarmasterBridge`
  repoint pulls hostile NPCs from `adventure_npcs` (Commit 3).
  Combat HUD path itself unchanged; `Combat::SocialEventTrigger`
  witness derivation should still produce the same observable
  behavior post-repoint.
- **Adventure creation / first message** — verify
  `Story.opening_message` renders as the first `AdventureMessage` of
  type `narrative` after Embellisher retirement, no Enrich-required
  state remains, the bulk-inserted `seed_facts` land in
  `adventure_narrative_facts`, and the player can take a first action
  against the new opening (Commit 7).
- **Admin story editor** — verify Enrich Story button is gone, Save
  still persists, and authoring a new story end-to-end still produces
  a playable adventure (Commit 7 + Commit 9).
- **Sidebar / sheet refresh after combat** — confirm the established
  bug class (sidebar-doesn't-refresh-after-buff) still doesn't
  regress under the new pipeline output shape (no Chronicler).
- **Initiative pause + resume** — paused-and-resumed adventures still
  produce coherent state with the slimmed ContextUpdate writes
  (combat + scene_summary only).
- **Roll-then-resolve** and **no-roll-resolve** — both should produce
  narrative output. The no-roll path is the most behaviorally novel
  (Mechanic now handles auto-success per Decision 15); the e2e must
  drive an action that takes the no-roll branch and assert the
  narrative still progresses.

**E2e tests to add (new flows introduced by this epic):**
- **Procedural map placement smoke test** — story save triggers
  `Maps::PlaceLocations`; resulting `adventure_locations` rows have
  consistent `(x, y)` for the same `story_id`; impromptu location
  insertion at runtime is reflected in subsequent distance math.
- **Facts-only world consistency** — the player references a
  not-introduced NPC, the SanityChecker flags the inconsistency
  using the `adventure_npcs` slice (no fallback to dying contexts).

**E2e tests to delete:**
- Any e2e exercising clue discovery, milestone advancement, or DM
  Brief redaction (those features no longer exist).

The "delete the production fix and re-run" verification rule from the
README still applies: when an e2e is updated to cover a new behavior,
revert the production change locally and confirm the e2e fails. If it
still passes, the assertion is too weak.

## Trello follow-ups (out of scope for this epic)

- **Richer map** — varied terrain (cells / zones / per-location override),
  A* journeys, admin canvas renderer for tuning. Scope decision (A/B/C)
  via spike before implementation.
- **`StoryNpc` / `StoryLocation` removal** — replace authored anchors
  with free-form seeding (possibly AI-assisted) at story creation time.
  Eventual full removal of both Story* models.

## Doc cross-references

- `docs/design_philosophy.md` §1, §11, §18 — the principles this epic
  applies.
- `docs/pipeline_steps.md` Decision 37 — the narrative facts store
  cutover this epic builds on.
- This file (`MICRO_CONTEXT_REMOVAL_EPIC.md`) — implementation plan;
  delete after the PR ships.
