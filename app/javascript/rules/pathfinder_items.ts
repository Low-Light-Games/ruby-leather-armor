/**
 * Pathfinder 1e Item & Equipment Mechanics
 *
 * Carry capacity, encumbrance, equipment bonuses, starting gold.
 * All mechanical data is Open Game Content under the OGL 1.0a.
 */

import type {
  ItemDefinition,
  OwnedItem,
  Currency,
  EquipmentBonuses,
  EquipmentStatBonuses,
  EquipmentSkillBonuses,
  EncumbranceTier,
  CarryCapacity,
  EquipmentSlot,
  ResolvedSlot,
} from './pathfinder_items_types';
import type { CreatureSize } from './pathfinder_combat';

// ── Module-level item definitions cache (set by GameDataContext) ──

let _itemDefinitions: ItemDefinition[] = [];

export function setItemDefinitions(items: ItemDefinition[]): void {
  _itemDefinitions = items;
}

export function getItemDefinitions(): ItemDefinition[] {
  return _itemDefinitions;
}

export function getItemById(id: string): ItemDefinition | undefined {
  return _itemDefinitions.find(i => i.id === id);
}

// ── Equipment Slots ──────────────────────────────────────────────

export const EQUIPMENT_SLOTS: { slot: EquipmentSlot; label: string; maxCount: number }[] = [
  { slot: 'armor',     label: 'Armor',     maxCount: 1 },
  { slot: 'shield',    label: 'Shield',    maxCount: 1 },
  { slot: 'head',      label: 'Head',      maxCount: 1 },
  { slot: 'headband',  label: 'Headband',  maxCount: 1 },
  { slot: 'eyes',      label: 'Eyes',      maxCount: 1 },
  { slot: 'shoulders', label: 'Shoulders', maxCount: 1 },
  { slot: 'neck',      label: 'Neck',      maxCount: 1 },
  { slot: 'chest',     label: 'Chest',     maxCount: 1 },
  { slot: 'body',      label: 'Body',      maxCount: 1 },
  { slot: 'belt',      label: 'Belt',      maxCount: 1 },
  { slot: 'wrists',    label: 'Wrists',    maxCount: 1 },
  { slot: 'hands',     label: 'Hands',     maxCount: 1 },
  { slot: 'ring',      label: 'Ring',      maxCount: 2 },
  { slot: 'feet',      label: 'Feet',      maxCount: 1 },
];

// ── Starting Gold by Class (OGC) ────────────────────────────────
// Average starting wealth for level 1 characters.

export const STARTING_GOLD: Record<string, number> = {
  barbarian: 105,
  bard: 105,
  cleric: 140,
  druid: 70,
  fighter: 175,
  monk: 35,
  paladin: 175,
  ranger: 175,
  rogue: 140,
  sorcerer: 70,
  wizard: 70,
};

export function getStartingGold(classId: string | null): number {
  if (!classId) return 0;
  return STARTING_GOLD[classId] ?? 0;
}

// ── Currency Helpers ─────────────────────────────────────────────

export const EMPTY_CURRENCY: Currency = { gold: 0, silver: 0, copper: 0, platinum: 0 };

/** Total number of all coins (for carry weight: 50 coins = 1 lb). */
export function totalCoins(c: Currency): number {
  return (c.gold || 0) + (c.silver || 0) + (c.copper || 0) + (c.platinum || 0);
}

/** Total value expressed in gold pieces (for cost comparison). */
export function totalGpValue(c: Currency): number {
  return (c.platinum || 0) * 10
       + (c.gold || 0)
       + (c.silver || 0) / 10
       + (c.copper || 0) / 100;
}

/** Create a currency with only gold pieces set (e.g. from starting gold). */
export function currencyFromGold(gp: number): Currency {
  return { gold: gp, silver: 0, copper: 0, platinum: 0 };
}

/** Format currency for display, omitting zero denominations. */
export function formatCurrency(c: Currency): string {
  const parts: string[] = [];
  if (c.platinum > 0) parts.push(`${c.platinum} pp`);
  if (c.gold > 0) parts.push(`${c.gold} gp`);
  if (c.silver > 0) parts.push(`${c.silver} sp`);
  if (c.copper > 0) parts.push(`${c.copper} cp`);
  return parts.length > 0 ? parts.join(', ') : '0 gp';
}

// ── Carry Capacity Table (OGC) ──────────────────────────────────
// Indexed by STR score. Each entry: [light, medium, heavy] max lbs.

const CARRY_CAPACITY_TABLE: [number, number, number][] = [
  [0, 0, 0],          // STR 0
  [3, 6, 10],         // STR 1
  [6, 13, 20],        // STR 2
  [10, 20, 30],       // STR 3
  [13, 26, 40],       // STR 4
  [16, 33, 50],       // STR 5
  [20, 40, 60],       // STR 6
  [23, 46, 70],       // STR 7
  [26, 53, 80],       // STR 8
  [30, 60, 90],       // STR 9
  [33, 66, 100],      // STR 10
  [38, 76, 115],      // STR 11
  [43, 86, 130],      // STR 12
  [50, 100, 150],     // STR 13
  [58, 116, 175],     // STR 14
  [66, 133, 200],     // STR 15
  [76, 153, 230],     // STR 16
  [86, 173, 260],     // STR 17
  [100, 200, 300],    // STR 18
  [116, 233, 350],    // STR 19
  [133, 266, 400],    // STR 20
  [153, 306, 460],    // STR 21
  [173, 346, 520],    // STR 22
  [200, 400, 600],    // STR 23
  [233, 466, 700],    // STR 24
  [266, 533, 800],    // STR 25
  [306, 613, 920],    // STR 26
  [346, 693, 1040],   // STR 27
  [400, 800, 1200],   // STR 28
  [466, 933, 1400],   // STR 29
];

/**
 * Get carry capacity thresholds for a given STR score and creature size.
 * Small creatures carry 3/4 of Medium capacity.
 */
export function getCarryCapacity(strScore: number, size: CreatureSize): CarryCapacity {
  const str = Math.max(strScore, 0);

  let caps: [number, number, number];
  if (str < CARRY_CAPACITY_TABLE.length) {
    caps = CARRY_CAPACITY_TABLE[str];
  } else {
    // For STR > 29: each +10 over 20 multiplies base values by 4
    const base = CARRY_CAPACITY_TABLE[20];
    const tens = Math.floor((str - 20) / 10);
    const remainder = (str - 20) % 10;
    const remIdx = Math.min(20 + remainder, CARRY_CAPACITY_TABLE.length - 1);
    const remCaps = CARRY_CAPACITY_TABLE[remIdx];
    const multiplier = Math.pow(4, tens);
    caps = [
      remCaps[0] * multiplier,
      remCaps[1] * multiplier,
      remCaps[2] * multiplier,
    ];
  }

  // Small creatures: 3/4 of Medium capacity
  if (size === 'Small') {
    return {
      light: Math.floor(caps[0] * 0.75),
      medium: Math.floor(caps[1] * 0.75),
      heavy: Math.floor(caps[2] * 0.75),
    };
  }

  return { light: caps[0], medium: caps[1], heavy: caps[2] };
}

// ── Weight Computation ───────────────────────────────────────────

/** Coin weight: 50 coins = 1 lb (all coin types weigh the same). */
export function coinWeight(coinCount: number): number {
  return coinCount / 50;
}

/**
 * Compute total carry weight from all owned items + currency.
 * All items count toward weight, not just equipped ones.
 * All coin types weigh the same: 50 coins = 1 lb.
 */
export function computeTotalWeight(
  ownedItems: OwnedItem[],
  currency: Currency,
): number {
  let weight = 0;

  for (const owned of ownedItems) {
    const def = getItemById(owned.itemId);
    if (!def) continue;
    weight += def.weight * owned.quantity;
  }

  weight += coinWeight(totalCoins(currency));

  return Math.round(weight * 100) / 100; // round to 2 decimal places
}

// ── Encumbrance ──────────────────────────────────────────────────

export function computeEncumbranceTier(
  totalWeight: number,
  capacity: CarryCapacity,
): EncumbranceTier {
  if (totalWeight <= capacity.light) return 'light';
  if (totalWeight <= capacity.medium) return 'medium';
  if (totalWeight <= capacity.heavy) return 'heavy';
  return 'overloaded';
}

export interface EncumbranceLimits {
  maxDex: number | null;  // null = no limit
  acp: number;            // armor check penalty (negative)
  runMultiplier: number;  // 0 = can't run
}

export function getEncumbranceLimits(tier: EncumbranceTier): EncumbranceLimits {
  switch (tier) {
    case 'light':
      return { maxDex: null, acp: 0, runMultiplier: 4 };
    case 'medium':
      return { maxDex: 3, acp: -3, runMultiplier: 4 };
    case 'heavy':
      return { maxDex: 1, acp: -6, runMultiplier: 3 };
    case 'overloaded':
      return { maxDex: 0, acp: -6, runMultiplier: 0 };
  }
}

// ── Equipment Bonus Aggregation ──────────────────────────────────

/**
 * Aggregate bonuses from all equipped items (armor, shield, max DEX, ACP, ASF).
 */
export function computeEquipmentBonuses(ownedItems: OwnedItem[]): EquipmentBonuses {
  const result: EquipmentBonuses = {
    armorBonus: 0,
    shieldBonus: 0,
    maxDexBonus: null,
    armorCheckPenalty: 0,
    arcaneSpellFailure: 0,
    speed30: null,
    speed20: null,
  };

  for (const owned of ownedItems) {
    if (!owned.equipped) continue;

    const def = getItemById(owned.itemId);
    if (!def) continue;

    result.armorBonus += def.armorBonus;
    result.shieldBonus += def.shieldBonus;
    result.armorCheckPenalty += def.armorCheckPenalty;
    result.arcaneSpellFailure += def.arcaneSpellFailure;

    // Max DEX: most restrictive wins (lowest non-null)
    if (def.maxDexBonus !== null) {
      result.maxDexBonus =
        result.maxDexBonus === null
          ? def.maxDexBonus
          : Math.min(result.maxDexBonus, def.maxDexBonus);
    }

    // Speed from armor
    if (def.itemType === 'armor') {
      if (def.speed30 !== null) result.speed30 = def.speed30;
      if (def.speed20 !== null) result.speed20 = def.speed20;
    }
  }

  return result;
}

/**
 * Compute stat bonuses from equipped item effects (same pattern as feat effects).
 */
export function computeEquipmentStatBonuses(
  ownedItems: OwnedItem[],
  characterLevel: number,
): EquipmentStatBonuses {
  const result: EquipmentStatBonuses = {
    ac: 0,
    fortSave: 0,
    refSave: 0,
    willSave: 0,
    initiative: 0,
    meleeAttack: 0,
    rangedAttack: 0,
    hp: 0,
  };

  for (const owned of ownedItems) {
    if (!owned.equipped) continue;

    const def = getItemById(owned.itemId);
    if (!def) continue;

    for (const effect of def.effects) {
      switch (effect.type) {
        case 'bonus': {
          if ('condition' in effect && effect.condition) break;

          switch (effect.target) {
            case 'ac':           result.ac += effect.bonus; break;
            case 'fort_save':    result.fortSave += effect.bonus; break;
            case 'ref_save':     result.refSave += effect.bonus; break;
            case 'will_save':    result.willSave += effect.bonus; break;
            case 'all_saves':
              result.fortSave += effect.bonus;
              result.refSave += effect.bonus;
              result.willSave += effect.bonus;
              break;
            case 'initiative':    result.initiative += effect.bonus; break;
            case 'attack':
              result.meleeAttack += effect.bonus;
              result.rangedAttack += effect.bonus;
              break;
            case 'melee_attack':  result.meleeAttack += effect.bonus; break;
            case 'ranged_attack': result.rangedAttack += effect.bonus; break;
          }
          break;
        }
        case 'hp_bonus': {
          const hpFromItem = Math.max(
            effect.perLevel * characterLevel,
            effect.minimum ?? 0,
          );
          result.hp += hpFromItem;
          break;
        }
      }
    }
  }

  return result;
}

/**
 * Compute skill bonuses from equipped item effects.
 */
export function computeEquipmentSkillBonuses(ownedItems: OwnedItem[]): EquipmentSkillBonuses {
  const bonuses: EquipmentSkillBonuses = {};

  for (const owned of ownedItems) {
    if (!owned.equipped) continue;

    const def = getItemById(owned.itemId);
    if (!def) continue;

    for (const effect of def.effects) {
      if (effect.type === 'skill_bonus') {
        bonuses[effect.skill] = (bonuses[effect.skill] || 0) + effect.bonus;
      }
    }
  }

  return bonuses;
}

// ── Effective DEX Modifier ───────────────────────────────────────

/**
 * Compute effective DEX modifier after armor and encumbrance caps.
 * Returns the capped DEX mod.
 */
export function effectiveDexMod(
  rawDexMod: number,
  equipMaxDex: number | null,
  encumbranceMaxDex: number | null,
): number {
  const caps = [equipMaxDex, encumbranceMaxDex].filter(
    (v): v is number => v !== null,
  );

  if (caps.length === 0) return rawDexMod;

  const lowestCap = Math.min(...caps);
  return Math.min(rawDexMod, lowestCap);
}

// ── Effective Speed ──────────────────────────────────────────────

/**
 * Compute effective speed after armor and encumbrance penalties.
 */
export function computeEffectiveSpeed(
  baseSpeed: number,
  equip: EquipmentBonuses,
  encumbrance: EncumbranceTier,
): number {
  // Armor may set a specific speed
  const armorSpeed = baseSpeed >= 30 ? equip.speed30 : equip.speed20;

  // Encumbrance (medium/heavy/overloaded) reduces speed
  const encSpeed =
    encumbrance === 'medium' || encumbrance === 'heavy' || encumbrance === 'overloaded'
      ? baseSpeed >= 30 ? 20 : 15
      : baseSpeed;

  const speeds = [armorSpeed, encSpeed].filter((v): v is number => v !== null);
  return speeds.length > 0 ? Math.min(...speeds) : baseSpeed;
}

// ── Slot Validation ──────────────────────────────────────────────

/**
 * Validate that equipping an item doesn't conflict with existing equipped items.
 * Returns an error message or null if valid.
 */
export function validateSlotEquip(
  ownedItems: OwnedItem[],
  itemToEquip: OwnedItem,
  itemDef: ItemDefinition,
): string | null {
  const targetSlot: ResolvedSlot = itemToEquip.slotOverride ?? itemDef.slot;

  if (targetSlot === 'none') return null; // no slot restriction

  const equippedInSlot = ownedItems.filter(oi => {
    if (!oi.equipped) return false;
    if (oi === itemToEquip) return false;

    const def = getItemById(oi.itemId);
    if (!def) return false;

    const oiSlot: ResolvedSlot = oi.slotOverride ?? def.slot;
    return oiSlot === targetSlot;
  });

  // Rings: allow 2 via ring_1/ring_2
  if (itemDef.slot === 'ring') {
    const ringSlots = ownedItems.filter(oi => {
      if (!oi.equipped || oi === itemToEquip) return false;
      const def = getItemById(oi.itemId);
      return def?.slot === 'ring';
    });
    if (ringSlots.length >= 2) {
      return 'Both ring slots are occupied';
    }
    return null;
  }

  if (equippedInSlot.length > 0) {
    return `Slot '${targetSlot}' is already occupied`;
  }

  return null;
}

/**
 * Compute total gold spent on owned items.
 */
export function computeItemsCost(ownedItems: OwnedItem[]): number {
  let total = 0;
  for (const owned of ownedItems) {
    const def = getItemById(owned.itemId);
    if (!def) continue;
    total += def.costGp * owned.quantity;
  }
  return Math.round(total * 100) / 100;
}
