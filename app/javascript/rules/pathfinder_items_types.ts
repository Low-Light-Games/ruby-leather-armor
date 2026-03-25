/**
 * Pathfinder 1e Item System — Type Definitions
 *
 * All mechanical data (item stats, slot definitions, carry capacity)
 * is Open Game Content under the OGL 1.0a.
 */

// ── Item types ───────────────────────────────────────────────────

export type ItemType = 'armor' | 'shield' | 'weapon' | 'gear' | 'potion' | 'wondrous' | 'ammunition';

// ── Equipment slots ──────────────────────────────────────────────

export type EquipmentSlot =
  | 'armor'
  | 'shield'
  | 'head'
  | 'headband'
  | 'eyes'
  | 'shoulders'
  | 'neck'
  | 'chest'
  | 'body'
  | 'belt'
  | 'wrists'
  | 'hands'
  | 'ring'
  | 'feet'
  | 'none';

/** Resolved slot for items that support multiple positions (e.g. rings) */
export type ResolvedSlot = EquipmentSlot | 'ring_1' | 'ring_2';

// ── Armor categories ─────────────────────────────────────────────

export type ArmorCategory = 'light' | 'medium' | 'heavy';

// ── Weapon properties ────────────────────────────────────────────

export type WeaponCategory = 'simple' | 'martial' | 'exotic';
export type WeaponType = 'melee' | 'ranged';

// ── Item effect (reuses feat effect schema) ──────────────────────

export type ItemEffect =
  | {
      type: 'bonus';
      target: string;
      bonus: number;
      bonusType?: string;
      condition?: string;
    }
  | {
      type: 'skill_bonus';
      skill: string;
      bonus: number;
    }
  | {
      type: 'hp_bonus';
      perLevel: number;
      minimum?: number;
    };

// ── Item definition (from API) ───────────────────────────────────

export interface ItemDefinition {
  id: string;
  name: string;
  itemType: ItemType;
  category: string | null;       // armor weight class, weapon proficiency group, etc.
  slot: EquipmentSlot;
  weight: number;                // lbs
  costGp: number;                // gold pieces

  // Armor/Shield stats
  armorBonus: number;
  shieldBonus: number;
  maxDexBonus: number | null;    // null = no limit
  armorCheckPenalty: number;     // negative number
  arcaneSpellFailure: number;    // percentage 0–100
  speed30: number | null;        // speed when wearing (base 30)
  speed20: number | null;        // speed when wearing (base 20)

  // Weapon stats
  weaponCategory: WeaponCategory | null;
  weaponType: WeaponType | null;
  damageDice: string | null;     // "1d8", "2d6"
  criticalRange: string | null;  // "19-20/x2", "x3"
  damageType: string | null;     // "slashing", "piercing", "bludgeoning"
  rangeIncrement: number | null; // feet

  // Flexible
  properties: Record<string, unknown>;
  effects: ItemEffect[];
  summary: string | null;
}

// ── Owned item entry (from sheet/adventure_sheet details) ────────

export interface OwnedItem {
  itemId: string;
  quantity: number;
  equipped: boolean;
  slotOverride: ResolvedSlot | null;
  /** Full definition from the server — present for dynamically-created items
   *  that do not exist in the static rules cache. */
  definition?: ItemDefinition;
}

// ── Currency ─────────────────────────────────────────────────────

export interface Currency {
  gold: number;
  silver: number;
  copper: number;
  platinum: number;
}

// ── Encumbrance ──────────────────────────────────────────────────

export type EncumbranceTier = 'light' | 'medium' | 'heavy' | 'overloaded';

export interface CarryCapacity {
  light: number;
  medium: number;
  heavy: number;
}

// ── Equipment bonus aggregation ──────────────────────────────────

export interface EquipmentBonuses {
  armorBonus: number;
  shieldBonus: number;
  maxDexBonus: number | null;      // null = no limit from equipment
  armorCheckPenalty: number;       // negative
  arcaneSpellFailure: number;      // percentage
  speed30: number | null;
  speed20: number | null;
}

export interface EquipmentStatBonuses {
  ac: number;
  fortSave: number;
  refSave: number;
  willSave: number;
  initiative: number;
  meleeAttack: number;
  rangedAttack: number;
  hp: number;
}

export interface EquipmentSkillBonuses {
  [skillName: string]: number;
}
