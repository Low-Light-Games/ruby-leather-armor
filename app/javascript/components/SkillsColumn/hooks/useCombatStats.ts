import { useMemo } from 'react';
import type { AttributeValues } from '../../../contexts/SheetsContext';
import type { OwnedItem, Currency, EquipmentBonuses, EncumbranceTier, CarryCapacity } from '../../../rules/pathfinder_items_types';
import type { RaceDefinition } from '../../../rules/pathfinder_races';
import type { ClassDefinition } from '../../../rules/pathfinder_classes';
import { abilityModifier } from '../../../rules/pathfinder_skills';
import {
  touchAC,
  flatFootedAC,
  fullAC,
  combatManeuverBonus,
  combatManeuverDefense,
} from '../../../rules/pathfinder_combat';
import {
  computeEquipmentBonuses,
  computeEquipmentStatBonuses,
  computeEquipmentSkillBonuses,
  computeTotalWeight,
  getCarryCapacity,
  computeEncumbranceTier,
  getEncumbranceLimits,
  effectiveDexMod as computeEffectiveDexMod,
  computeEffectiveSpeed,
} from '../../../rules/pathfinder_items';
import type { EncumbranceLimits } from '../../../rules/pathfinder_items';
import type { EquipmentSkillBonuses } from '../../../rules/pathfinder_items_types';
import {
  computeBAB,
  computeBaseSave,
  computeFeatStatBonuses,
} from '../../../rules/pathfinder_feats';

export interface CombatStats {
  ac: number;
  tAC: number;
  ffAC: number;
  cmb: number;
  cmd: number;
  bab: number;
  initiative: number;
  fort: number;
  ref: number;
  will: number;
  hpBonus: number;
  speed: number;
  armorBonus: number;
  shieldBonus: number;
  totalACP: number;
  arcaneSpellFailure: number;
  encumbranceTier: EncumbranceTier;
  totalWeight: number;
  carryCapacity: CarryCapacity;
}

interface UseCombatStatsParams {
  finalAttributes: AttributeValues;
  race: RaceDefinition | undefined;
  classDef: ClassDefinition | undefined;
  currentLevel: number;
  selectedFeats: string[];
  selectedItems: OwnedItem[];
  currentCurrency: Currency;
}

interface UseCombatStatsResult {
  combatStats: CombatStats;
  /** Total armor check penalty (equipment + encumbrance) — needed by useSkills */
  totalACP: number;
  /** Skill bonuses from equipped item effects — needed by useSkills */
  equipSkillBonuses: EquipmentSkillBonuses;
  /** Equipment bonuses (armor, shield, ACP, ASF, speed) */
  equipBonuses: EquipmentBonuses;
  /** Encumbrance limits (maxDex, ACP, run multiplier) */
  encumbranceLimits: EncumbranceLimits;
}

export function useCombatStats({
  finalAttributes,
  race,
  classDef,
  currentLevel,
  selectedFeats,
  selectedItems,
  currentCurrency,
}: UseCombatStatsParams): UseCombatStatsResult {
  // Feat stat bonuses (AC, saves, initiative, HP, etc.)
  const featStatBonuses = useMemo(
    () => computeFeatStatBonuses(selectedFeats, currentLevel),
    [selectedFeats, currentLevel],
  );

  // Equipment bonuses from equipped items
  const equipBonuses = useMemo(
    () => computeEquipmentBonuses(selectedItems),
    [selectedItems],
  );

  const equipStatBonuses = useMemo(
    () => computeEquipmentStatBonuses(selectedItems, currentLevel),
    [selectedItems, currentLevel],
  );

  const equipSkillBonuses = useMemo(
    () => computeEquipmentSkillBonuses(selectedItems),
    [selectedItems],
  );

  // Carry weight & encumbrance
  const totalWeight = useMemo(
    () => computeTotalWeight(selectedItems, currentCurrency),
    [selectedItems, currentCurrency],
  );

  const carryCapacity = useMemo(() => {
    const size = race?.size ?? 'Medium';
    return getCarryCapacity(finalAttributes.strength, size);
  }, [finalAttributes.strength, race]);

  const encumbranceTier = useMemo(
    () => computeEncumbranceTier(totalWeight, carryCapacity),
    [totalWeight, carryCapacity],
  );

  const encumbranceLimits = useMemo(
    () => getEncumbranceLimits(encumbranceTier),
    [encumbranceTier],
  );

  // Total ACP (armor + encumbrance)
  const totalACP = useMemo(
    () => equipBonuses.armorCheckPenalty + encumbranceLimits.acp,
    [equipBonuses.armorCheckPenalty, encumbranceLimits.acp],
  );

  // Combat derived stats
  const combatStats = useMemo((): CombatStats => {
    const rawDexMod = abilityModifier(finalAttributes.dexterity);
    const strMod = abilityModifier(finalAttributes.strength);
    const conMod = abilityModifier(finalAttributes.constitution);
    const wisMod = abilityModifier(finalAttributes.wisdom);
    const size = race?.size ?? 'Medium';
    const bab = classDef ? computeBAB(classDef.bab, currentLevel) : 0;

    // Effective DEX mod (capped by armor + encumbrance)
    const effDexMod = computeEffectiveDexMod(
      rawDexMod,
      equipBonuses.maxDexBonus,
      encumbranceLimits.maxDex,
    );

    // AC with armor, shield, feats, and item effect bonuses
    const acBonuses = featStatBonuses.ac + equipStatBonuses.ac;
    const ac = fullAC(effDexMod, size, equipBonuses.armorBonus, equipBonuses.shieldBonus, acBonuses);
    const tAC = touchAC(effDexMod, size, acBonuses);
    const ffAC = flatFootedAC(size, equipBonuses.armorBonus, equipBonuses.shieldBonus);

    const cmb = combatManeuverBonus(bab, strMod, size);
    const cmd = combatManeuverDefense(bab, strMod, effDexMod, size);
    const initiative = effDexMod + featStatBonuses.initiative + equipStatBonuses.initiative;

    // Saves
    const fortGood = classDef ? classDef.goodSaves.includes('fort') : false;
    const refGood = classDef ? classDef.goodSaves.includes('ref') : false;
    const willGood = classDef ? classDef.goodSaves.includes('will') : false;
    const fort = computeBaseSave(fortGood, currentLevel) + conMod +
                 featStatBonuses.fortSave + equipStatBonuses.fortSave;
    const ref = computeBaseSave(refGood, currentLevel) + effDexMod +
                featStatBonuses.refSave + equipStatBonuses.refSave;
    const will = computeBaseSave(willGood, currentLevel) + wisMod +
                 featStatBonuses.willSave + equipStatBonuses.willSave;

    // HP bonus from feats + items
    const hpBonus = featStatBonuses.hp + equipStatBonuses.hp;

    // Speed
    const baseSpeed = race?.speed ?? 30;
    const speed = computeEffectiveSpeed(baseSpeed, equipBonuses, encumbranceTier);

    // Arcane spell failure
    const arcaneSpellFailure = equipBonuses.arcaneSpellFailure;

    return {
      ac, tAC, ffAC, cmb, cmd, bab, initiative, fort, ref, will, hpBonus,
      totalACP, speed, arcaneSpellFailure, encumbranceTier,
      armorBonus: equipBonuses.armorBonus,
      shieldBonus: equipBonuses.shieldBonus,
      totalWeight, carryCapacity,
    };
  }, [
    finalAttributes, race, classDef, currentLevel,
    featStatBonuses, equipBonuses, equipStatBonuses,
    encumbranceLimits, encumbranceTier, totalWeight, carryCapacity, totalACP,
  ]);

  return { combatStats, totalACP, equipSkillBonuses, equipBonuses, encumbranceLimits };
}
