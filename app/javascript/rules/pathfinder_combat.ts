/**
 * Pathfinder 1e combat derived stats.
 *
 * AC size modifier: Small +1, Medium 0
 * CMB/CMD special size modifier: Small -1, Medium 0
 *
 * AC = 10 + DEX mod (capped) + size + armor + shield + natural + deflection + feat/item bonuses
 * Touch AC = 10 + DEX mod (capped) + size + deflection + feat/item bonuses (excludes armor, shield, natural)
 * Flat-Footed AC = 10 + size + armor + shield + natural + deflection (excludes DEX, dodge)
 * CMB = BAB + STR mod + CMB size mod
 * CMD = 10 + BAB + STR mod + DEX mod (capped) + CMD size mod
 */

export type CreatureSize = 'Small' | 'Medium';

/** Size modifier for AC and attack rolls */
export function acSizeModifier(size: CreatureSize): number {
  return size === 'Small' ? 1 : 0;
}

/** Special size modifier for CMB and CMD */
export function cmbSizeModifier(size: CreatureSize): number {
  return size === 'Small' ? -1 : 0;
}

/**
 * Touch AC (excludes armor, shield, natural armor).
 * Uses effective DEX mod (already capped by armor/encumbrance).
 */
export function touchAC(
  effectiveDexMod: number,
  size: CreatureSize,
  acBonuses = 0,
): number {
  return 10 + effectiveDexMod + acSizeModifier(size) + acBonuses;
}

/**
 * Flat-Footed AC (excludes DEX and dodge; includes armor + shield).
 */
export function flatFootedAC(
  size: CreatureSize,
  armorBonus = 0,
  shieldBonus = 0,
): number {
  return 10 + acSizeModifier(size) + armorBonus + shieldBonus;
}

/**
 * Full AC = 10 + effectiveDex + size + armor + shield + feat/item AC bonuses
 */
export function fullAC(
  effectiveDexMod: number,
  size: CreatureSize,
  armorBonus: number,
  shieldBonus: number,
  acBonuses: number,
): number {
  return 10 + effectiveDexMod + acSizeModifier(size) + armorBonus + shieldBonus + acBonuses;
}

export function combatManeuverBonus(
  bab: number,
  strMod: number,
  size: CreatureSize,
): number {
  return bab + strMod + cmbSizeModifier(size);
}

export function combatManeuverDefense(
  bab: number,
  strMod: number,
  effectiveDexMod: number,
  size: CreatureSize,
): number {
  return 10 + bab + strMod + effectiveDexMod + cmbSizeModifier(size);
}
