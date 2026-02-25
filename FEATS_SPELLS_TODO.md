# Feats & Spells — Structured Data TODO

Entries marked with `{ type: 'special' }` effects are mechanically present but use
a free-text description fallback instead of a fully structured effect type.
These should eventually be converted to more specific effect types so the engine
can apply them programmatically.

---

## Feats with `special` effects to fully structure

### Combat Feats (`pathfinder_feats_combat.ts`)

| Feat | Reason |
|---|---|
| Catch Off-Guard | Flat-footed condition vs improvised weapons — needs condition-application model |
| Combat Reflexes | AoO while flat-footed — needs combat-state modifier |
| Critical Mastery | Apply two critical effects simultaneously — needs compound-effect model |
| Disruptive | Increase defensive casting DC — needs DC-modifier effect |
| Far Shot | Reduce range increment penalties — needs range-penalty model |
| Greater Feint | Extended feint (lasts until next turn for all attacks) — needs duration model |
| Improved Feint | Feint as move action — needs action-economy model |
| Improved Overrun | Forced overrun (no avoidance) — needs combat-maneuver modifier |
| Improved Unarmed Strike | Lethal/nonlethal choice + no AoO — needs weapon-property modifier |
| Improvised Weapon Mastery | Larger damage die + crit range + no AoO — compound weapon modifier |
| Lunge | +5 reach / -2 AC trade-off — needs temporary reach + AC penalty |
| Manyshot | Fire two arrows on first attack — needs extra-projectile model |
| Rapid Reload | Faster reload by weapon type — needs action-economy modifier |
| Shatter Defenses | Frightened foe flat-footed — needs condition-propagation model |
| Shield Master | Add shield enhancement to attack/damage — needs equipment-bonus transfer |
| Shield Slam | Free bull rush on shield bash + wall damage — compound maneuver |
| Snatch Arrows | Catch + throw back deflected projectile — needs deflect-counter model |
| Spellbreaker | Failed defensive casting provokes AoO — needs triggered-reaction model |
| Step Up | Immediate 5-ft step to follow retreating foe — needs reaction model |
| Two-Weapon Rend | Bonus damage on dual hit — needs conditional-damage model |

### General Feats (`pathfinder_feats_general.ts`)

| Feat | Reason |
|---|---|
| Diehard | Act while dying + auto-stabilize — needs HP-state model |
| Endurance | Sleep in armor without fatigue — needs rest/fatigue model |
| Eschew Materials | Ignore material components ≤ 1 gp — needs component-bypass model |
| Leadership | Cohort + followers — complex subsystem, deferred |
| Natural Spell | Cast in wild shape — needs form-casting model |
| Turn Undead | Channel energy variant (flee) — needs channel-variant model |

---

## Spells with `special` effects to fully structure

### Abjuration (`pathfinder_spells_abjuration.ts`)

| Spell | Reason |
|---|---|
| Remove Fear | Suppress existing fear with new save — needs condition-suppression model |
| Sanctuary | Will save to attack; ends if warded creature attacks — needs triggered-ward model |

### Divination (`pathfinder_spells_divination.ts`)

| Spell | Reason |
|---|---|
| Guidance | +1 competence to next attack/save/skill then ends — needs single-use-bonus model |

### Enchantment (`pathfinder_spells_enchantment.ts`)

| Spell | Reason |
|---|---|
| Command | One-word commands with varied behaviour — needs command-action model |

### Evocation (`pathfinder_spells_evocation.ts`)

| Spell | Reason |
|---|---|
| Shocking Grasp | +3 attack vs metal armor — needs conditional-attack-bonus model |

### Illusion (`pathfinder_spells_illusion.ts`)

| Spell | Reason |
|---|---|
| Color Spray | HD-tiered conditions (unconscious/blinded/stunned) — needs tiered-condition model |

### Necromancy (`pathfinder_spells_necromancy.ts`)

| Spell | Reason |
|---|---|
| Bleed | Resume dying — needs HP-state manipulation |
| Stabilize | Stabilize dying creature — needs HP-state manipulation |
| Chill Touch | Dual mode (living: STR damage; undead: flee) — needs multi-target-type model |
| Inflict Light Wounds | Negative energy (damages living, heals undead) — needs dual-mode-energy model |
| Ray of Enfeeblement | STR penalty via ranged touch — needs ability-penalty model |

### Transmutation (`pathfinder_spells_transmutation.ts`)

| Spell | Reason |
|---|---|
| Enlarge Person | Size change with compound stat adjustments — needs size-change model |
| Expeditious Retreat | Enhancement to base speed — partially structurable as `movement` |
| Feather Fall | Slow fall for multiple creatures — needs fall-rate model |
| Jump | Scaling enhancement to Acrobatics (jumping) — partially structurable as `skill_bonus` |
| Longstrider | Enhancement to base speed — partially structurable as `movement` |
| Reduce Person | Size change with compound stat adjustments — needs size-change model |
| Shillelagh | Weapon enhancement + damage dice increase — needs weapon-modification model |

---

## Planned: Migrate Feats & Spells to SQL Database

**Status:** Planned (not yet started)
**Priority:** Do this when feat definitions move to the DB or the DM needs to grant/modify feats programmatically.

### Rationale

Parameterized feats (Skill Focus, Weapon Focus, Spell Focus, etc.) and repeatable
feats benefit from relational storage. A proper SQL schema lets the server validate
prerequisites, the DM engine grant/remove feats, and simplifies querying.

### Schema Design

```
sheet_feats
  id             bigint PK
  sheet_id       bigint FK → sheets
  feat_id        string      (references the TS/DB feat definition)
  choice         string NULL (the weapon, skill, or school chosen — NULL for non-parameterised feats)
  created_at     timestamp
  updated_at     timestamp

adventure_sheet_feats
  id                  bigint PK
  adventure_sheet_id  bigint FK → adventure_sheets
  feat_id             string
  choice              string NULL
  created_at          timestamp
  updated_at          timestamp
```

### Migration Steps

1. Create `sheet_feats` and `adventure_sheet_feats` tables.
2. Migrate existing `details['feats']` JSON arrays into `sheet_feats` rows.
   - Plain feat IDs → `{ feat_id: 'power_attack', choice: NULL }`.
   - Compound IDs (interim format `feat_id::choice`) → `{ feat_id: 'skill_focus', choice: 'Perception' }`.
3. Migrate `adventure_sheets.details['feats']` similarly.
4. Move feat *definitions* from static TypeScript files to a `feat_definitions` table.
5. Add server-side prerequisite validation in the Rails model/controller.
6. Remove `details['feats']` from the JSON column.
7. Update frontend to fetch feat definitions from an API and selections from the new association.

### Also Consider (same migration wave)

- Move spell definitions to `spell_definitions` table.
- Create `sheet_spells` / `adventure_sheet_spells` pivot tables with a
  `storage_type` column (`'known'` | `'spellbook'`) to replace `details['knownSpells']`
  and `details['spellbook']`.

---

## Roadmap: Backend Stat Engine & Data Migration

The frontend currently owns ~100% of the game-mechanics computation (derived stats,
feat effects, spell eligibility, prerequisite checks). This is duplicated across
`SkillsColumn.tsx` (~810 lines) and `AdventurePlay.tsx` (~660 lines), and the
backend DM prompt has no access to computed stats like AC, saves, or skill totals.

The plan below is ordered by dependency and incremental deliverability.

### Phase 1 — Feat & Spell Definitions to Database (Seeders)

**Goal:** Move the ~155 feat and ~104 spell definitions from static TypeScript files
into PostgreSQL tables, seeded from Rails seed files.

| Step | Description |
|------|-------------|
| 1.1 | Create `feat_definitions` table: `id (string PK)`, `name`, `category`, `summary`, `repeatable (bool)`, `choice_type (nullable)`, `prerequisites (jsonb)`, `effects (jsonb)` |
| 1.2 | Create `spell_definitions` table: `id (string PK)`, `name`, `school`, `summary`, `description`, `casting_time`, `range`, `duration`, `saving_throw`, `spell_resistance`, `components (jsonb)`, `class_levels (jsonb)`, `effects (jsonb)` |
| 1.3 | Write seed files (`db/seeds/feats.rb`, `db/seeds/spells.rb`) that convert the existing TS data into DB rows. A one-time script can parse the TS files or we hand-transcribe the JSONB payloads. |
| 1.4 | Add `Feat` and `Spell` Rails models with lookup scopes (`by_category`, `for_class`, etc.) |
| 1.5 | Add read-only REST endpoints: `GET /api/feats` and `GET /api/spells` (with filters: `?class=wizard&max_level=1`) |
| 1.6 | Update frontend to fetch definitions from the API instead of importing static TS arrays. Keep the TS type interfaces for the response shape. |
| 1.7 | Delete the static TS definition files (`pathfinder_feats_combat.ts`, `pathfinder_feats_general.ts`, `pathfinder_spells_*.ts`) |

### Phase 2 — Feat & Spell Selections to Pivot Tables

**Goal:** Replace the JSONB `details.feats` / `details.knownSpells` / `details.spellbook`
arrays with proper relational pivot tables.

| Step | Description |
|------|-------------|
| 2.1 | Create `sheet_feats` (`sheet_id FK`, `feat_id FK → feat_definitions`, `choice nullable`) |
| 2.2 | Create `adventure_sheet_feats` (same shape, FK to `adventure_sheets`) |
| 2.3 | Create `sheet_spells` (`sheet_id FK`, `spell_id FK`, `storage_type: 'known' \| 'spellbook'`) |
| 2.4 | Create `adventure_sheet_spells` (same shape, FK to `adventure_sheets`) |
| 2.5 | Data migration: iterate existing `sheets` and `adventure_sheets`, parse `details.feats` (handling compound `feat_id::choice` format) into `sheet_feats` / `adventure_sheet_feats` rows. Parse `details.knownSpells` and `details.spellbook` into `sheet_spells` / `adventure_sheet_spells`. |
| 2.6 | Update `SheetsController` and `AdventureSheetsController` to CRUD through the pivot models instead of mutating JSONB |
| 2.7 | Update frontend to send/receive feat/spell selections as nested resource arrays instead of flat ID lists |
| 2.8 | Remove `feats`, `knownSpells`, `spellbook`, `spells` keys from `details` JSONB |

### Phase 3 — Server-Side Derived Stats Engine

**Goal:** The backend becomes the single source of truth for computed character stats.
Frontend becomes a thin display/interaction layer.

| Step | Description |
|------|-------------|
| 3.1 | Create `CharacterStats::Calculator` service (Ruby). Port the Pathfinder math: racial modifiers → final ability scores → ability modifiers → BAB → saves → AC variants → CMB/CMD → initiative → skill totals → feat bonuses → HP. |
| 3.2 | Add a `derived_stats (jsonb)` column to both `sheets` and `adventure_sheets`. Compute and cache on every save (`after_save` callback). |
| 3.3 | Expose `derived_stats` in the existing JSON responses (no new endpoint needed — it's just another column). |
| 3.4 | Update DM prompt (`DungeonMaster::Prompts`) to read computed stats directly (AC, saves, skill bonuses, etc.) so the AI can make informed decisions. |
| 3.5 | Simplify `SkillsColumn.tsx`: remove the `combatStats` and `calculatedSkills` useMemo blocks; read from `sheet.derived_stats` received from the API. |
| 3.6 | Simplify `AdventurePlay.tsx`: remove the `derivedStats` useMemo block; read from `adventure.adventure_sheet.derived_stats`. |
| 3.7 | Delete the frontend helper functions that are now redundant (`computeFeatSkillBonuses`, `computeFeatStatBonuses`, `computeBAB`, `baseSave`, etc.) |

### Phase 4 — Server-Side Prerequisite & Spell Eligibility Validation

**Goal:** The backend enforces game rules, not just the frontend.

| Step | Description |
|------|-------------|
| 4.1 | Add prerequisite checking to `SheetFeat` model (`validate :meets_prerequisites`). Uses the `feat_definitions.prerequisites` JSONB against the sheet's current stats and existing feats. |
| 4.2 | Add spell eligibility checking to `SheetSpell` model (class spell list, slot limits, ability score minimums). |
| 4.3 | Return validation errors as structured JSON so the frontend can display them inline. |
| 4.4 | Remove the frontend `checkAllPrerequisites`, `canSelectFeat`, `canSelectSpell` functions (keep only the UI to display server-sent eligibility flags). |
| 4.5 | Add a `GET /api/feats/eligible?sheet_id=X` endpoint that returns all feats annotated with `{ eligible: bool, unmet: [...] }` for the feat picker. Similarly for spells. |

### Phase 5 — DM Programmatic Actions

**Goal:** The DM AI can grant/remove feats, modify spells, adjust gold/HP, and level up
characters through structured actions, not just narrative.

| Step | Description |
|------|-------------|
| 5.1 | Extend DM response JSON schema to include `actions: [{ type: 'grant_feat', feat_id, choice? }, { type: 'add_spell', spell_id }, { type: 'modify_hp', delta }, ...]` |
| 5.2 | Process actions in `DungeonMasterService` after parsing the AI response — create/destroy pivot records, adjust `adventure_sheet` columns, recompute `derived_stats` |
| 5.3 | Return the updated `adventure_sheet` (with fresh `derived_stats`) in the message response so the frontend reflects changes instantly |

---

## Future Work

- [ ] Define new structured effect types for the patterns above (size-change, condition-propagation, action-economy, etc.)
- [ ] Convert each `special` entry to the appropriate structured type
- [ ] Add level 2+ spells (currently only levels 0–1 are included)
- [ ] Add spells from non-Core sources (APG, Ultimate Magic, etc.)
- [ ] Add feats from non-Core sources (APG, Ultimate Combat, etc.)
- [ ] Multi-level BAB/saves (currently only level-1 base values are used; scaling formulas needed)
- [ ] Equipment/armor system (AC from armor, weapon damage, encumbrance)
- [ ] Conditions/buffs engine (temporary modifiers from spells, abilities, items)