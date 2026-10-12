export type CreatureSize = 'Small' | 'Medium';

const BASE_ARMOR_CLASS = 10;
const BASE_COMBAT_MANEUVER_DEFENSE = 10;

export function acSizeModifier(size: CreatureSize): number {
  return size === 'Small' ? 1 : 0;
}

export function cmbSizeModifier(size: CreatureSize): number {
  return size === 'Small' ? -1 : 0;
}

// Callers pass a DEX mod already capped by armor and encumbrance.
export function touchAC(
  effectiveDexMod: number,
  size: CreatureSize,
  acBonuses = 0,
): number {
  return BASE_ARMOR_CLASS + effectiveDexMod + acSizeModifier(size) + acBonuses;
}

export function flatFootedAC(
  size: CreatureSize,
  armorBonus = 0,
  shieldBonus = 0,
): number {
  return BASE_ARMOR_CLASS + acSizeModifier(size) + armorBonus + shieldBonus;
}

export function fullAC(
  effectiveDexMod: number,
  size: CreatureSize,
  armorBonus: number,
  shieldBonus: number,
  acBonuses: number,
): number {
  return BASE_ARMOR_CLASS + effectiveDexMod + acSizeModifier(size) + armorBonus + shieldBonus + acBonuses;
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
  return BASE_COMBAT_MANEUVER_DEFENSE + bab + strMod + effectiveDexMod + cmbSizeModifier(size);
}
