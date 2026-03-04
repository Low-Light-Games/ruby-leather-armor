# TimeKeeper

Pipeline step that estimates in-game time for any player action and orchestrates
time-related utilities (Harbinger encounter checks, GameClock advancement).
Runs after Ruling, before the output phase.

---

## Purpose

Every player action consumes in-game time. TimeKeeper universally determines
how much — whether the action is a journey to a known destination, a combat
round, a rest, a Take 20 attempt, or freeform waiting/crafting. It is the
single orchestrator of all time logic in the budget pipeline.

TimeKeeper follows a strict protocol for every time-consuming task:

1. **Estimate** how many hours the action takes (code-first, AI fallback)
2. **Consult Harbinger** — will an encounter interrupt those hours?
3. **Advance GameClock** with the actual hours (which may be less if interrupted)

---

## Architecture

```
                     ┌─────────────────────────┐
                     │    TimeKeeper (step)     │
                     │                          │
                     │  1. Estimate hours       │
                     │  2. Consult Harbinger    │
                     │  3. Call GameClock       │
                     └─────────┬───────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                 ▼
     Harbinger (utility)  GameClock (utility)  AI (fallback)
     encounter rolls      clock advance        freeform estimation
     code-only            code-only            cheap model
```

---

## Estimation Sources (priority order)

### 1. Journey — known destination (code-first)

When `intent[:destination]` resolves to a `StoryLocation` with a
`LocationConnection`, TimeKeeper computes deterministically:

- Base speed from `derived_stats["speed"]` (accounts for armor + encumbrance)
- Terrain modifier from `DmConfig.terrain_speed_modifiers` (admin-configurable)
- `estimated_hours = distance_miles / speed_mph`

No AI call is made.

### 2. Journey — freeform (AI)

When the player has a destination that doesn't match a known location,
TimeKeeper asks AI to estimate hours and approximate distance/direction.

### 3. Combat (code shortcut)

When combat is active: 0.0017 hours (~6 seconds per round). No AI call.

### 4. Rest (code shortcut)

Detected by keyword matching on the intention. Long rest = 8 hours,
short rest = 1 hour. No AI call.

### 5. Take 20 (code shortcut)

Detected from ruling outcome or intention. ~40 minutes (0.67 hours)
per PF1e rules. No AI call.

### 6. AI fallback (everything else)

A focused prompt asks a cheap model for `hours_elapsed` and `reasoning`.
Covers: waiting, crafting, studying, searching, unconsciousness, and any
freeform actions not caught by the code paths above.

### Compound actions

If the player describes multiple sequential actions ("rest then travel"),
the AI prompt instructs estimation for the **first action only**. Remaining
actions are handled in subsequent pipeline runs.

---

## Harbinger Consultation

After estimation, TimeKeeper checks if Harbinger should run:
- Skipped if estimated hours < 0.01 (less than ~36 seconds)
- Skipped if no `EncounterTable` exists for the story
- Skipped if `hours_since_last_encounter_check + estimated_hours` is below
  the table's `check_frequency_hours`

If Harbinger runs and returns an encounter, TimeKeeper uses the interrupted
`hours_granted` instead of the full estimate.

---

## GameClock Advancement

After Harbinger resolves, TimeKeeper calls `GameClock.advance_clock!` with
the actual hours. GameClock handles:
- Hour/day arithmetic
- Light conditions derivation (dawn/day/dusk/night)
- `hours_since_last_rest` tracking (reset on rest actions)
- `hours_since_last_encounter_check` tracking
- Threshold checks (fatigue, hunger)

---

## Terrain Speed Modifiers

Admin-configurable via `DmConfig.terrain_speed_modifiers`. PF1e defaults:

| Terrain     | Modifier |
|-------------|----------|
| road        | 1.0      |
| trail       | 0.75     |
| urban       | 1.0      |
| coast       | 0.75     |
| forest      | 0.5      |
| swamp       | 0.5      |
| desert      | 0.75     |
| river       | 0.5      |
| mountain    | 0.25     |
| underground | 0.5      |

---

## Files

| File | Purpose |
|------|---------|
| `app/services/dungeon_master/steps/time_keeper.rb` | Pipeline step |
| `app/services/dungeon_master/templates/time_keeper.text.erb` | AI prompt (freeform estimation) |
| `app/services/dungeon_master/utilities/game_clock.rb` | Clock advancement utility |
| `app/services/dungeon_master/utilities/harbinger.rb` | Encounter checking utility |

---

## Model Recommendation

**Recommended:** gpt-4.1-nano, gpt-5-nano, gpt-4o-mini

The AI path produces a tiny JSON object (2-3 fields). The task is simple
time estimation — no complex reasoning needed. Nano models handle it well.

**Token budget:** 300 (non-reasoning) / 1200 (reasoning).
