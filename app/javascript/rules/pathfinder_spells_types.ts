/**
 * Type definitions for Pathfinder 1e Core Rulebook spells.
 * All content is Open Game Content — mechanical rules only.
 */

// ─── Spell School ────────────────────────────────────────────

export type SpellSchool =
  | 'abjuration'
  | 'conjuration'
  | 'divination'
  | 'enchantment'
  | 'evocation'
  | 'illusion'
  | 'necromancy'
  | 'transmutation'
  | 'universal';

// ─── Spell Components ────────────────────────────────────────

/** V=Verbal, S=Somatic, M=Material, F=Focus, DF=Divine Focus */
export type SpellComponent = 'V' | 'S' | 'M' | 'F' | 'DF';

// ─── Spell Effects ───────────────────────────────────────────

export type SpellEffect =
  // ── Direct damage ──
  | {
      type: 'damage';
      dice: string;                          // e.g. '1d3', '1d4+1', '1d6'
      damageType: string;                    // e.g. 'fire', 'force', 'acid'
      perCasterLevel?: boolean;              // dice scale with CL?
      maxDice?: number;                      // cap on scaling dice
      missileCount?: {                       // Magic Missile–style
        base: number;
        perLevels: number;
        max: number;
      };
    }

  // ── Healing ──
  | {
      type: 'healing';
      dice: string;
      bonusPerLevel?: number;
      maxBonus?: number;
    }

  // ── AC bonus ──
  | {
      type: 'ac_bonus';
      bonus: number | string;                // number or formula like '2 + CL/3 max 5'
      bonusType: string;                     // armor, shield, deflection, etc.
      maxDexBonus?: number;
    }

  // ── Save bonus ──
  | {
      type: 'save_bonus';
      save: 'fort' | 'ref' | 'will' | 'all';
      bonus: number;
      bonusType?: string;
      condition?: string;
    }

  // ── Attack bonus ──
  | {
      type: 'attack_bonus';
      bonus: number | string;
      bonusType?: string;
      condition?: string;
    }

  // ── Skill bonus ──
  | {
      type: 'skill_bonus';
      skill: string;
      bonus: number;
      bonusType?: string;
    }

  // ── Ability score bonus/penalty ──
  | {
      type: 'ability_modifier';
      ability: string;
      bonus: number;
      bonusType?: string;
    }

  // ── Stat penalty/debuff ──
  | {
      type: 'debuff';
      target: string;
      penalty: number;
      penaltyType?: string;
    }

  // ── Apply a condition ──
  | {
      type: 'condition';
      condition: string;
      hitDiceLimit?: number;
      totalHDLimit?: number;
      duration?: string;
    }

  // ── Area creation / control ──
  | {
      type: 'area';
      shape: string;
      size: string;
      effect: string;
    }

  // ── Summon creature ──
  | {
      type: 'summon';
      creature: string;
      count?: string;
    }

  // ── Temporary hit points ──
  | { type: 'temp_hp'; amount: string }

  // ── Energy resistance ──
  | { type: 'resistance'; energyType: string | 'all'; amount: number }

  // ── Damage bonus ──
  | {
      type: 'damage_bonus';
      bonus: string;
      damageType?: string;
      condition?: string;
    }

  // ── Deflection AC ──
  | {
      type: 'deflection_ac';
      bonus: string;
      bonusType: string;
    }

  // ── Spell resistance ──
  | { type: 'sr_bonus'; bonus: number | string }

  // ── Immunity / protection ──
  | {
      type: 'immunity';
      target: string;
      condition?: string;
    }

  // ── Movement modification ──
  | { type: 'movement'; description: string }

  // ── Detection / sensing ──
  | { type: 'detection'; detects: string; range?: string }

  // ── General utility ──
  | { type: 'utility'; description: string }

  // ── Special (fallback — entries tracked in FEATS_SPELLS_TODO.md) ──
  | { type: 'special'; description: string };

// ─── Spell Definition ────────────────────────────────────────

export interface SpellDefinition {
  id: string;
  name: string;
  school: SpellSchool;
  subschool?: string;
  descriptors?: string[];
  /** Spell level keyed by class id (e.g. { cleric: 1, wizard: 1 }) */
  classLevels: Record<string, number>;
  components: SpellComponent[];
  materialComponent?: string;
  castingTime: string;
  range: string;
  duration: string;
  savingThrow: string;
  spellResistance: boolean;
  effects: SpellEffect[];
  summary: string;
}
