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
  acSizeModifier,
  cmbSizeModifier,
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
import type { CombatStatCalculations, CombatStatCalculation } from '../combatHelp/combatCalcTypes';

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
  combatStatCalculations: CombatStatCalculations;
  totalACP: number;
  equipSkillBonuses: EquipmentSkillBonuses;
  equipBonuses: EquipmentBonuses;
  encumbranceLimits: EncumbranceLimits;
}

const ENCUMBRANCE_LABEL: Record<EncumbranceTier, string> = {
  light: 'Light load',
  medium: 'Medium load',
  heavy: 'Heavy load',
  overloaded: 'Overloaded',
};

function dexCapFootnote(raw: number, effective: number): string | undefined {
  if (raw === effective) return undefined;
  return 'Your Dexterity modifier is reduced to the effective value above when limited by worn armor (maximum Dexterity) and/or carrying capacity.';
}

function buildSpeedFootnotes(
  baseSpeed: number,
  equip: EquipmentBonuses,
  encumbrance: EncumbranceTier,
  effectiveSpeed: number,
): string[] {
  const lines: string[] = [`Racial base speed: ${baseSpeed} ft.`];
  const armorCap = baseSpeed >= 30 ? equip.speed30 : equip.speed20;
  if (armorCap != null) {
    lines.push(
      `Armor limits speed to ${armorCap} ft (rules for ${baseSpeed >= 30 ? '30 ft or higher' : 'below 30 ft'} base).`,
    );
  }
  if (encumbrance === 'medium' || encumbrance === 'heavy' || encumbrance === 'overloaded') {
    const encCap = baseSpeed >= 30 ? 20 : 15;
    lines.push(`Medium load or heavier caps speed at ${encCap} ft for your base move rate.`);
  }
  lines.push(`Speed on this sheet: ${effectiveSpeed} ft (most restrictive applicable limit).`);
  return lines;
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
  const featStatBonuses = useMemo(
    () => computeFeatStatBonuses(selectedFeats, currentLevel),
    [selectedFeats, currentLevel],
  );

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

  const { combatStats, combatStatCalculations } = useMemo(() => {
    const rawDexMod = abilityModifier(finalAttributes.dexterity);
    const strMod = abilityModifier(finalAttributes.strength);
    const conMod = abilityModifier(finalAttributes.constitution);
    const wisMod = abilityModifier(finalAttributes.wisdom);
    const size = race?.size ?? 'Medium';
    const bab = classDef ? computeBAB(classDef.bab, currentLevel) : 0;

    const effDexMod = computeEffectiveDexMod(
      rawDexMod,
      equipBonuses.maxDexBonus,
      encumbranceLimits.maxDex,
    );

    const acBonuses = featStatBonuses.ac + equipStatBonuses.ac;
    const sizeAcMod = acSizeModifier(size);
    const sizeCmbMod = cmbSizeModifier(size);

    const ac = fullAC(effDexMod, size, equipBonuses.armorBonus, equipBonuses.shieldBonus, acBonuses);
    const tAC = touchAC(effDexMod, size, acBonuses);
    const ffAC = flatFootedAC(size, equipBonuses.armorBonus, equipBonuses.shieldBonus);

    const cmb = combatManeuverBonus(bab, strMod, size);
    const cmd = combatManeuverDefense(bab, strMod, effDexMod, size);
    const initiative = effDexMod + featStatBonuses.initiative + equipStatBonuses.initiative;

    const fortGood = classDef ? classDef.goodSaves.includes('fort') : false;
    const refGood = classDef ? classDef.goodSaves.includes('ref') : false;
    const willGood = classDef ? classDef.goodSaves.includes('will') : false;
    const fortBase = computeBaseSave(fortGood, currentLevel);
    const refBase = computeBaseSave(refGood, currentLevel);
    const willBase = computeBaseSave(willGood, currentLevel);
    const fort = fortBase + conMod + featStatBonuses.fortSave + equipStatBonuses.fortSave;
    const ref = refBase + effDexMod + featStatBonuses.refSave + equipStatBonuses.refSave;
    const will = willBase + wisMod + featStatBonuses.willSave + equipStatBonuses.willSave;

    const hpBonus = featStatBonuses.hp + equipStatBonuses.hp;

    const baseSpeed = race?.speed ?? 30;
    const speed = computeEffectiveSpeed(baseSpeed, equipBonuses, encumbranceTier);

    const arcaneSpellFailure = equipBonuses.arcaneSpellFailure;

    const stats: CombatStats = {
      ac,
      tAC,
      ffAC,
      cmb,
      cmd,
      bab,
      initiative,
      fort,
      ref,
      will,
      hpBonus,
      totalACP,
      speed,
      arcaneSpellFailure,
      encumbranceTier,
      armorBonus: equipBonuses.armorBonus,
      shieldBonus: equipBonuses.shieldBonus,
      totalWeight,
      carryCapacity,
    };

    const dexNote = dexCapFootnote(rawDexMod, effDexMod);

    const acAdditive = [
      { value: 10, label: 'Base' },
      {
        value: effDexMod,
        label: rawDexMod !== effDexMod ? 'Dexterity (effective to AC)' : 'Dexterity',
      },
      ...(sizeAcMod !== 0 ? [{ value: sizeAcMod, label: 'Small size (AC)' }] : []),
      ...(equipBonuses.armorBonus > 0 ? [{ value: equipBonuses.armorBonus, label: 'Armor' }] : []),
      ...(equipBonuses.shieldBonus > 0 ? [{ value: equipBonuses.shieldBonus, label: 'Shield' }] : []),
      ...(featStatBonuses.ac !== 0 ? [{ value: featStatBonuses.ac, label: 'Feats' }] : []),
      ...(equipStatBonuses.ac !== 0 ? [{ value: equipStatBonuses.ac, label: 'Worn items' }] : []),
    ];

    const touchAdditive = [
      { value: 10, label: 'Base' },
      {
        value: effDexMod,
        label: rawDexMod !== effDexMod ? 'Dexterity (effective)' : 'Dexterity',
      },
      ...(sizeAcMod !== 0 ? [{ value: sizeAcMod, label: 'Small size (AC)' }] : []),
      ...(featStatBonuses.ac !== 0 ? [{ value: featStatBonuses.ac, label: 'Feats' }] : []),
      ...(equipStatBonuses.ac !== 0 ? [{ value: equipStatBonuses.ac, label: 'Worn items' }] : []),
    ];

    const ffAdditive = [
      { value: 10, label: 'Base' },
      ...(sizeAcMod !== 0 ? [{ value: sizeAcMod, label: 'Small size (AC)' }] : []),
      ...(equipBonuses.armorBonus > 0 ? [{ value: equipBonuses.armorBonus, label: 'Armor' }] : []),
      ...(equipBonuses.shieldBonus > 0 ? [{ value: equipBonuses.shieldBonus, label: 'Shield' }] : []),
    ];

    const initiativeAdditive = [
      {
        value: effDexMod,
        label: rawDexMod !== effDexMod ? 'Dexterity (effective)' : 'Dexterity',
      },
      ...(featStatBonuses.initiative !== 0
        ? [{ value: featStatBonuses.initiative, label: 'Feats' }]
        : []),
      ...(equipStatBonuses.initiative !== 0
        ? [{ value: equipStatBonuses.initiative, label: 'Worn items' }]
        : []),
    ];

    const fortAdditive = [
      { value: fortBase, label: 'Class Fortitude progression' },
      { value: conMod, label: 'Constitution' },
      ...(featStatBonuses.fortSave !== 0 ? [{ value: featStatBonuses.fortSave, label: 'Feats' }] : []),
      ...(equipStatBonuses.fortSave !== 0
        ? [{ value: equipStatBonuses.fortSave, label: 'Worn items' }]
        : []),
    ];

    const refAdditive = [
      { value: refBase, label: 'Class Reflex progression' },
      {
        value: effDexMod,
        label: rawDexMod !== effDexMod ? 'Dexterity (effective)' : 'Dexterity',
      },
      ...(featStatBonuses.refSave !== 0 ? [{ value: featStatBonuses.refSave, label: 'Feats' }] : []),
      ...(equipStatBonuses.refSave !== 0 ? [{ value: equipStatBonuses.refSave, label: 'Worn items' }] : []),
    ];

    const willAdditive = [
      { value: willBase, label: 'Class Will progression' },
      { value: wisMod, label: 'Wisdom' },
      ...(featStatBonuses.willSave !== 0 ? [{ value: featStatBonuses.willSave, label: 'Feats' }] : []),
      ...(equipStatBonuses.willSave !== 0 ? [{ value: equipStatBonuses.willSave, label: 'Worn items' }] : []),
    ];

    const cmdAdditive = [
      { value: 10, label: 'Base' },
      { value: bab, label: 'Base attack bonus' },
      { value: strMod, label: 'Strength' },
      {
        value: effDexMod,
        label: rawDexMod !== effDexMod ? 'Dexterity (effective)' : 'Dexterity',
      },
      ...(sizeCmbMod !== 0 ? [{ value: sizeCmbMod, label: 'Small size (maneuvers)' }] : []),
    ];

    const cmbAdditive = [
      { value: bab, label: 'Base attack bonus' },
      { value: strMod, label: 'Strength' },
      ...(sizeCmbMod !== 0 ? [{ value: sizeCmbMod, label: 'Small size (maneuvers)' }] : []),
    ];

    const babAdditive: CombatStatCalculation['additive'] =
      classDef != null
        ? [{ value: bab, label: `Class levels (${currentLevel}) — ${classDef.bab} BAB progression` }]
        : [{ value: 0, label: 'No class selected' }];

    const hpCalc: CombatStatCalculation =
      hpBonus === 0
        ? {
            total: 0,
            additive: [],
            footnotes: ['No unconditional hit point bonuses from feats or worn items on this sheet.'],
          }
        : {
            total: hpBonus,
            additive: [
              ...(featStatBonuses.hp !== 0 ? [{ value: featStatBonuses.hp, label: 'Feats' }] : []),
              ...(equipStatBonuses.hp !== 0 ? [{ value: equipStatBonuses.hp, label: 'Worn items' }] : []),
            ],
          };

    const acpCalc: CombatStatCalculation =
      totalACP === 0
        ? {
            total: 0,
            additive: [],
            footnotes: ['No armor check penalty from worn armor, shields, or encumbrance.'],
          }
        : {
            total: totalACP,
            additive: [
              ...(equipBonuses.armorCheckPenalty !== 0
                ? [{ value: equipBonuses.armorCheckPenalty, label: 'Armor & shield' }]
                : []),
              ...(encumbranceLimits.acp !== 0
                ? [{ value: encumbranceLimits.acp, label: 'Encumbrance load' }]
                : []),
            ],
          };

    const asfCalc: CombatStatCalculation =
      arcaneSpellFailure === 0
        ? {
            total: 0,
            additive: [],
            footnotes: ['No arcane spell failure from worn armor or shields.'],
          }
        : {
            total: arcaneSpellFailure,
            additive: [{ value: arcaneSpellFailure, label: 'Worn armor & shield' }],
          };

    const w = Math.round(totalWeight * 10) / 10;
    const encCalc: CombatStatCalculation = {
      total: w,
      additive: [{ value: w, label: 'Total carried weight (gear + coins)' }],
      footnotes: [
        `Current load: ${ENCUMBRANCE_LABEL[encumbranceTier]}.`,
        `Maximum weights for your Strength and size — light ≤ ${carryCapacity.light}, medium ≤ ${carryCapacity.medium}, heavy ≤ ${carryCapacity.heavy} lb.`,
      ],
    };

    const calculations: CombatStatCalculations = {
      ac: { total: ac, additive: acAdditive, footnotes: dexNote ? [dexNote] : undefined },
      touchAc: { total: tAC, additive: touchAdditive, footnotes: dexNote ? [dexNote] : undefined },
      flatFooted: {
        total: ffAC,
        additive: ffAdditive,
        footnotes: [
          'Flat-footed AC here includes base, size, armor, and shield only (matches this sheet’s engine).',
        ],
      },
      bab: { total: bab, additive: babAdditive },
      initiative: {
        total: initiative,
        additive: initiativeAdditive,
        footnotes: dexNote ? [dexNote] : undefined,
      },
      speed: {
        total: speed,
        additive: [],
        footnotes: buildSpeedFootnotes(baseSpeed, equipBonuses, encumbranceTier, speed),
      },
      cmb: { total: cmb, additive: cmbAdditive },
      cmd: { total: cmd, additive: cmdAdditive, footnotes: dexNote ? [dexNote] : undefined },
      fort: { total: fort, additive: fortAdditive },
      ref: {
        total: ref,
        additive: refAdditive,
        footnotes: dexNote
          ? ['Reflex uses the same effective Dexterity modifier as AC (armor and encumbrance caps).']
          : undefined,
      },
      will: { total: will, additive: willAdditive },
      hpBonus: hpCalc,
      armorBonus: {
        total: equipBonuses.armorBonus,
        additive:
          equipBonuses.armorBonus > 0
            ? [{ value: equipBonuses.armorBonus, label: 'Equipped armor bonus to AC' }]
            : [],
        footnotes:
          equipBonuses.armorBonus === 0 ? ['No armor bonus from equipped armor.'] : undefined,
      },
      shieldBonus: {
        total: equipBonuses.shieldBonus,
        additive:
          equipBonuses.shieldBonus > 0
            ? [{ value: equipBonuses.shieldBonus, label: 'Equipped shield bonus to AC' }]
            : [],
        footnotes:
          equipBonuses.shieldBonus === 0 ? ['No shield bonus from an equipped shield.'] : undefined,
      },
      acp: acpCalc,
      arcaneSpellFailure: asfCalc,
      encumbrance: encCalc,
    };

    return { combatStats: stats, combatStatCalculations: calculations };
  }, [
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
  ]);

  return {
    combatStats,
    combatStatCalculations,
    totalACP,
    equipSkillBonuses,
    equipBonuses,
    encumbranceLimits,
  };
}
