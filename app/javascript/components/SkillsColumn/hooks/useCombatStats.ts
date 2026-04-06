import { useMemo } from 'react';
import type { AttributeValues } from '../../../contexts/SheetsContext';
import type { OwnedItem, Currency, EquipmentBonuses } from '../../../rules/pathfinder_items_types';
import type { RaceDefinition } from '../../../rules/pathfinder_races';
import type { ClassDefinition } from '../../../rules/pathfinder_classes';
import {
  computeEquipmentBonuses,
  computeEquipmentStatBonuses,
  computeEquipmentSkillBonuses,
  computeTotalWeight,
  getCarryCapacity,
  computeEncumbranceTier,
  getEncumbranceLimits,
  type EncumbranceLimits,
} from '../../../rules/pathfinder_items';
import type { EquipmentSkillBonuses } from '../../../rules/pathfinder_items_types';
import { computeFeatStatBonuses } from '../../../rules/pathfinder_feats';
import { featListRawEntries, FeatMigrationUtils } from '../../../rules/pathfinder_feat_pools';
import type { CombatStatCalculations } from '../combatHelp/combatCalcTypes';
import {
  calculateCombatStatsAndCalculations,
  type CombatStats,
} from './computeSheetCombatStats';

export type { CombatStats };

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
  combatStatCalculations: CombatStatCalculations;
  totalACP: number;
  equipSkillBonuses: EquipmentSkillBonuses;
  equipBonuses: EquipmentBonuses;
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
  const featStatBonuses = useMemo(() => {
    const raw = featListRawEntries(FeatMigrationUtils.migrateToPooledFormat(selectedFeats));
    return computeFeatStatBonuses(raw, currentLevel);
  }, [selectedFeats, currentLevel]);

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

  const totalACP = useMemo(
    () => equipBonuses.armorCheckPenalty + encumbranceLimits.acp,
    [equipBonuses.armorCheckPenalty, encumbranceLimits.acp],
  );

  const { combatStats, combatStatCalculations } = useMemo(
    () =>
      calculateCombatStatsAndCalculations({
        finalAttributes,
        race,
        classDef,
        currentLevel,
        featStatBonuses,
        equipBonuses,
        equipStatBonuses,
        encumbranceLimits,
        encumbranceTier,
        totalWeight,
        carryCapacity,
        totalACP,
      }),
    [
      finalAttributes,
      race,
      classDef,
      currentLevel,
      featStatBonuses,
      equipBonuses,
      equipStatBonuses,
      encumbranceLimits,
      encumbranceTier,
      totalWeight,
      carryCapacity,
      totalACP,
    ],
  );

  return {
    combatStats,
    combatStatCalculations,
    totalACP,
    equipSkillBonuses,
    equipBonuses,
    encumbranceLimits,
  };
}
