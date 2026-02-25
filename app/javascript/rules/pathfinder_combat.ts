/**
 * Pathfinder 1e combat derived stats.
 *
 * AC size modifier: Small +1, Medium 0
 * CMB/CMD special size modifier: Small -1, Medium 0
 *
 * Touch AC = 10 + DEX mod + AC size mod  (excludes armor, shield, natural armor)
 * Flat-Footed AC = 10 + AC size mod      (excludes DEX, dodge; would include armor/shield/natural if tracked)
 * CMB = BAB + STR mod + CMB size mod
 * CMD = 10 + BAB + STR mod + DEX mod + CMD size mod  (CMD size mod = CMB size mod)
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

export function touchAC(dexMod: number, size: CreatureSize): number {
  return 10 + dexMod + acSizeModifier(size);
}

export function flatFootedAC(size: CreatureSize): number {
  // Would add armor + shield + natural armor when tracked
  return 10 + acSizeModifier(size);
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
  dexMod: number,
  size: CreatureSize,
): number {
  return 10 + bab + strMod + dexMod + cmbSizeModifier(size);
}
