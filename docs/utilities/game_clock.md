# GameClock

Deterministic clock advancement utility. Pure code, no AI.

---

## Purpose

GameClock is the single source of truth for advancing the adventure's
`time_context`. It handles hour/day arithmetic, derives light conditions,
tracks fatigue and encounter timers, and checks threshold alerts.

Called by:
- **TimeKeeper** (budget pipeline) after Harbinger resolves
- **EdgePipeline** after the unified model returns `time_update`

---

## Interface

```ruby
# Advance the clock by N hours
ctx = DungeonMaster::Utilities::GameClock.advance_clock!(
  adventure, hours, intent: intent
)

# Derive light conditions from an hour
DungeonMaster::Utilities::GameClock.light_for_hour(14)  # => "day"

# Check fatigue/hunger thresholds
alerts = DungeonMaster::Utilities::GameClock.check_thresholds(ctx)
# => [{ type: :fatigue, hours_awake: 18.5 }]
```

---

## Light Conditions

Deterministically derived from `current_hour`:

| Condition | Hours |
|-----------|-------|
| dawn      | 5-6   |
| day       | 7-17  |
| dusk      | 18-19 |
| night     | 20-4  |

---

## Clock Update Logic

1. `new_hour = (current_hour + hours) % 24`
2. `adventure_day += floor((current_hour + hours) / 24)`
3. `light_conditions` derived from new hour
4. `hours_since_last_rest += hours` (reset to 0 on rest actions)
5. `hours_since_last_encounter_check += hours`
6. Persisted to `adventure.time_context`

---

## Threshold Checks

After clock advancement, `check_thresholds` returns alerts:

| Threshold | Trigger | Future |
|-----------|---------|--------|
| Fatigue | `hours_since_last_rest >= 16` | Active |
| Hunger | `hours_since_last_meal >= 24` | Planned |
| Buff expiry | Active effects tick down | Planned |
| Light source burn | Torches/lanterns | Planned |

---

## time_context Schema

JSONB column on Adventure with default:

```json
{
  "current_hour": 8,
  "adventure_day": 1,
  "light_conditions": "day",
  "hours_since_last_rest": 0,
  "hours_since_last_encounter_check": 0
}
```

Managed entirely by code. Readable by AI steps (narrate, edge pipeline).

---

## File

`app/services/dungeon_master/utilities/game_clock.rb`
