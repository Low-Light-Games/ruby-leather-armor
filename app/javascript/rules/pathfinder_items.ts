// All mechanical data is Open Game Content under the OGL 1.0a.

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

export const EMPTY_CURRENCY: Currency = { gold: 0, silver: 0, copper: 0, platinum: 0 };

export function totalCoins(c: Currency): number {
  return (c.gold || 0) + (c.silver || 0) + (c.copper || 0) + (c.platinum || 0);
}

export function totalGpValue(c: Currency): number {
  return (c.platinum || 0) * 10
       + (c.gold || 0)
       + (c.silver || 0) / 10
       + (c.copper || 0) / 100;
}

export function currencyFromGold(gp: number): Currency {
  return { gold: gp, silver: 0, copper: 0, platinum: 0 };
}

export function formatCurrency(c: Currency): string {
  const parts: string[] = [];
  if (c.platinum > 0) parts.push(`${c.platinum} pp`);
  if (c.gold > 0) parts.push(`${c.gold} gp`);
  if (c.silver > 0) parts.push(`${c.silver} sp`);
  if (c.copper > 0) parts.push(`${c.copper} cp`);
  return parts.length > 0 ? parts.join(', ') : '0 gp';
}

type LoadLimitsLbs = [light: number, medium: number, heavy: number];

const CARRY_CAPACITY_BY_STRENGTH: LoadLimitsLbs[] = [
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

const SMALL_CREATURE_CARRY_FACTOR = 0.75;
const COINS_PER_POUND = 50;

// Past the table, every 10 points of STR above 20 quadruples the 20-29 row.
function extrapolatedCarryCapacity(str: number): LoadLimitsLbs {
  const tensAboveTwenty = Math.floor((str - 20) / 10);
  const onesDigitRow = Math.min(20 + (str - 20) % 10, CARRY_CAPACITY_BY_STRENGTH.length - 1);
  const [light, medium, heavy] = CARRY_CAPACITY_BY_STRENGTH[onesDigitRow];
  const multiplier = Math.pow(4, tensAboveTwenty);
  return [light * multiplier, medium * multiplier, heavy * multiplier];
}

export function getCarryCapacity(strScore: number, size: CreatureSize): CarryCapacity {
  const str = Math.max(strScore, 0);
  const [light, medium, heavy] = str < CARRY_CAPACITY_BY_STRENGTH.length
    ? CARRY_CAPACITY_BY_STRENGTH[str]
    : extrapolatedCarryCapacity(str);

  if (size === 'Small') {
    return {
      light: Math.floor(light * SMALL_CREATURE_CARRY_FACTOR),
      medium: Math.floor(medium * SMALL_CREATURE_CARRY_FACTOR),
      heavy: Math.floor(heavy * SMALL_CREATURE_CARRY_FACTOR),
    };
  }

  return { light, medium, heavy };
}

export function coinWeight(coinCount: number): number {
  return coinCount / COINS_PER_POUND;
}

// Unequipped items count too: everything owned is carried.
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

  return roundToHundredths(weight);
}

function roundToHundredths(value: number): number {
  return Math.round(value * 100) / 100;
}

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

    if (def.maxDexBonus !== null) {
      result.maxDexBonus =
        result.maxDexBonus === null
          ? def.maxDexBonus
          : Math.min(result.maxDexBonus, def.maxDexBonus);
    }

    if (def.itemType === 'armor') {
      if (def.speed30 !== null) result.speed30 = def.speed30;
      if (def.speed20 !== null) result.speed20 = def.speed20;
    }
  }

  return result;
}

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

export function computeEffectiveSpeed(
  baseSpeed: number,
  equip: EquipmentBonuses,
  encumbrance: EncumbranceTier,
): number {
  const armorSpeed = baseSpeed >= 30 ? equip.speed30 : equip.speed20;
  const slowedByLoad = encumbrance === 'medium' || encumbrance === 'heavy' || encumbrance === 'overloaded';
  const encumberedSpeed = slowedByLoad ? (baseSpeed >= 30 ? 20 : 15) : baseSpeed;

  const speeds = [armorSpeed, encumberedSpeed].filter((v): v is number => v !== null);
  return speeds.length > 0 ? Math.min(...speeds) : baseSpeed;
}

const MAX_EQUIPPED_RINGS = 2;

export function validateSlotEquip(
  ownedItems: OwnedItem[],
  itemToEquip: OwnedItem,
  itemDef: ItemDefinition,
): string | null {
  const targetSlot: ResolvedSlot = itemToEquip.slotOverride ?? itemDef.slot;

  if (targetSlot === 'none') return null;

  if (itemDef.slot === 'ring') {
    const otherEquippedRings = ownedItems.filter(oi => {
      if (!oi.equipped || oi === itemToEquip) return false;
      const def = getItemById(oi.itemId);
      return def?.slot === 'ring';
    });
    if (otherEquippedRings.length >= MAX_EQUIPPED_RINGS) {
      return 'Both ring slots are occupied';
    }
    return null;
  }

  const equippedInSlot = ownedItems.filter(oi => {
    if (!oi.equipped) return false;
    if (oi === itemToEquip) return false;

    const def = getItemById(oi.itemId);
    if (!def) return false;

    const oiSlot: ResolvedSlot = oi.slotOverride ?? def.slot;
    return oiSlot === targetSlot;
  });

  if (equippedInSlot.length > 0) {
    return `Slot '${targetSlot}' is already occupied`;
  }

  return null;
}

export function computeItemsCost(ownedItems: OwnedItem[]): number {
  let total = 0;
  for (const owned of ownedItems) {
    const def = getItemById(owned.itemId);
    if (!def) continue;
    total += def.costGp * owned.quantity;
  }
  return roundToHundredths(total);
}
