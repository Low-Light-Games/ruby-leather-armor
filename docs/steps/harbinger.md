# Harbinger

Deterministic encounter-checking utility. Simulates time passage in segments
and rolls against encounter tables. Called by TimeKeeper when significant
time passes.

Renamed from `TimeSpanResolver`, then refactored from a pipeline step into
a utility module. Harbinger no longer computes speed, distance, or
destinations — all of that is handled by TimeKeeper before calling Harbinger.

---

## Purpose

When TimeKeeper determines that a meaningful amount of time passes (travel,
rest, crafting, waiting), Harbinger simulates the passage in segments. Each
segment is a roll against the story's encounter table. If an encounter
triggers, the passage is interrupted and fewer hours are granted than
originally requested.

---

## Interface

```ruby
DungeonMaster::Utilities::Harbinger.consult(
  hours_needed: 10.0,
  adventure: @adventure,
  terrain: "forest",
  party_level: 3,
  speed_mph: 1.5,       # nil for non-journeys
  is_journey: true,
  ai: @ai,              # optional, for encounter expansion
  config: @config,       # optional
  log: @log              # optional
)
# => { interrupted: false, stop_reason: :arrived, hours_granted: 10.0,
#      distance_covered_miles: 15.0, narrative_seed: nil, encounter_entry: nil }
```

---

## How It Works

1. **Receive** `hours_needed` and optional journey data from TimeKeeper
2. **Segment** the time by the encounter table's `check_frequency_hours`
   (default 4 hours)
3. **Roll for encounters** per segment using the story's `EncounterTable`
4. If an encounter triggers:
   - Compute the exact hour within the segment where it occurs
   - Expand the encounter entry into narrative via an AI call (if available)
   - Return with `interrupted: true` and the actual `hours_granted`
5. If journey fatigue triggers (8+ hours of continuous travel):
   - Return with `stop_reason: :rest_needed`
6. If no interruption: return the full hours as `hours_granted`
7. For journeys: track `distance_covered_miles` using the provided `speed_mph`

---

## Stop Reasons

| Reason | Meaning |
|--------|---------|
| `:completed` | Non-journey time passage finished without incident |
| `:arrived` | Journey completed, player reached destination |
| `:encounter` | Random encounter interrupted the passage |
| `:rest_needed` | 8+ hours of continuous travel triggered fatigue |

---

## Encounter Expansion

When an encounter triggers, `expand_encounter` checks if the entry is
`fixed?` (pre-written) or needs AI expansion. Dynamic entries use the
`encounter_expansion` template to generate a contextual narrative seed.

---

## Files

| File | Purpose |
|------|---------|
| `app/services/dungeon_master/utilities/harbinger.rb` | Utility module |
| `app/services/dungeon_master/templates/encounter_expansion.text.erb` | Encounter expansion prompt |

---

## Encounter Tables

Harbinger uses the `EncounterTable` and `EncounterTableEntry` models.
Each story can have an encounter table with entries keyed by terrain type
and level range. The table's `check_frequency_hours` determines how often
encounters are rolled during extended passages.

If no encounter table exists for the story, Harbinger is skipped entirely
(TimeKeeper checks this before calling).
