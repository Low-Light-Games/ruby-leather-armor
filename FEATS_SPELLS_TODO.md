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

## Future Work

- [ ] Define new structured effect types for the patterns above (size-change, condition-propagation, action-economy, etc.)
- [ ] Convert each `special` entry to the appropriate structured type
- [ ] Add level 2+ spells (currently only levels 0–1 are included)
- [ ] Add spells from non-Core sources (APG, Ultimate Magic, etc.)
- [ ] Add feats from non-Core sources (APG, Ultimate Combat, etc.)
