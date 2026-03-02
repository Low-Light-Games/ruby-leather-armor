import { useState, useCallback } from 'react';
import type { AttributeType, AdventureSheet, DerivedStats } from '../../../types';
import type { RollResultDisplay } from '../../RollResultModal';
import type { DamageRollResult } from '../../../rules/dice';
import { formatMod, ABILITY_ABBR } from '../../../utils/formatting';
import { rollD20 } from '../../../rules/dice';
import { rollWeaponDamage as calcWeaponDamage, rollSpellDamage as calcSpellDamage, rollUnarmedDamage as calcUnarmedDamage } from '../../../rules/damage';
import { getSpellById } from '../../../rules/pathfinder_spells';
import { getClassById } from '../../../rules/pathfinder_classes';

interface UseRollsResult {
  rollDisplay: RollResultDisplay | null;
  damageDisplay: DamageRollResult | null;
  clearRoll: () => void;
  clearDamage: () => void;
  rollMeleeAttack: () => void;
  rollRangedAttack: () => void;
  rollFort: () => void;
  rollRef: () => void;
  rollWill: () => void;
  rollInitiative: () => void;
  rollAbility: (attr: AttributeType) => void;
  rollSkill: (skillName: string, total: number) => void;
  rollWeaponDamage: (itemId: string) => void;
  rollSpellDamage: (spellId: string) => void;
  rollUnarmedDamage: () => void;
  rollConcentration: () => void;
  concentrationMod: number | null;
}

export function useRolls(ds: DerivedStats | null, sheet?: AdventureSheet | null): UseRollsResult {
  const [rollDisplay, setRollDisplay] = useState<RollResultDisplay | null>(null);
  const [damageDisplay, setDamageDisplay] = useState<DamageRollResult | null>(null);

  const doRoll = useCallback((label: string, modifier: number, modifierLabel?: string) => {
    const result = rollD20(modifier);
    setRollDisplay({ label, result, modifierLabel });
  }, []);

  const rollMeleeAttack = useCallback(() => {
    if (!ds) return;
    doRoll('Melee Attack', ds.melee_attack, `BAB ${formatMod(ds.bab)} + STR ${formatMod(ds.mods.strength)}`);
  }, [ds, doRoll]);

  const rollRangedAttack = useCallback(() => {
    if (!ds) return;
    doRoll('Ranged Attack', ds.ranged_attack, `BAB ${formatMod(ds.bab)} + DEX ${formatMod(ds.mods.dexterity)}`);
  }, [ds, doRoll]);

  const rollFort = useCallback(() => {
    if (!ds) return;
    doRoll('Fortitude Save', ds.fort, `Fort ${formatMod(ds.fort)}`);
  }, [ds, doRoll]);

  const rollRef = useCallback(() => {
    if (!ds) return;
    doRoll('Reflex Save', ds.ref, `Ref ${formatMod(ds.ref)}`);
  }, [ds, doRoll]);

  const rollWill = useCallback(() => {
    if (!ds) return;
    doRoll('Will Save', ds.will, `Will ${formatMod(ds.will)}`);
  }, [ds, doRoll]);

  const rollInitiative = useCallback(() => {
    if (!ds) return;
    doRoll('Initiative', ds.initiative, `Init ${formatMod(ds.initiative)}`);
  }, [ds, doRoll]);

  const rollAbility = useCallback((attr: AttributeType) => {
    if (!ds) return;
    const mod = ds.mods[attr];
    doRoll(`${ABILITY_ABBR[attr]} Check`, mod, `${ABILITY_ABBR[attr]} ${formatMod(mod)}`);
  }, [ds, doRoll]);

  const rollSkill = useCallback((skillName: string, total: number) => {
    doRoll(`${skillName} Check`, total, `Skill ${formatMod(total)}`);
  }, [doRoll]);

  const rollWeaponDamage = useCallback((itemId: string) => {
    if (!ds || !sheet) return;
    const result = calcWeaponDamage(itemId, sheet, ds);
    if (result) setDamageDisplay(result);
  }, [ds, sheet]);

  const rollSpellDamage = useCallback((spellId: string) => {
    if (!sheet) return;
    const spell = getSpellById(spellId);
    if (!spell) return;
    const result = calcSpellDamage(spell, sheet.level);
    if (result) setDamageDisplay(result);
  }, [sheet]);

  const rollUnarmedDamage = useCallback(() => {
    if (!ds || !sheet) return;
    setDamageDisplay(calcUnarmedDamage(sheet, ds));
  }, [ds, sheet]);

  const concentrationMod = (() => {
    if (!ds || !sheet?.character_class) return null;
    const cls = getClassById(sheet.character_class);
    if (!cls?.spellcasting) return null;
    const abilityKey = cls.spellcasting.ability as AttributeType;
    const abilityMod = ds.mods[abilityKey] ?? 0;
    const casterLevel = sheet.level;
    return casterLevel + abilityMod;
  })();

  const rollConcentration = useCallback(() => {
    if (concentrationMod === null || !ds || !sheet?.character_class) return;
    const cls = getClassById(sheet.character_class);
    const abilityName = cls?.spellcasting?.ability ?? 'unknown';
    const abbr = ABILITY_ABBR[abilityName as AttributeType] ?? abilityName.slice(0, 3).toUpperCase();
    doRoll('Concentration', concentrationMod,
      `CL ${sheet.level} + ${abbr} ${formatMod(ds.mods[abilityName as AttributeType] ?? 0)}`);
  }, [concentrationMod, ds, sheet, doRoll]);

  return {
    rollDisplay,
    damageDisplay,
    clearRoll: () => setRollDisplay(null),
    clearDamage: () => setDamageDisplay(null),
    rollMeleeAttack,
    rollRangedAttack,
    rollFort,
    rollRef,
    rollWill,
    rollInitiative,
    rollAbility,
    rollSkill,
    rollWeaponDamage,
    rollSpellDamage,
    rollUnarmedDamage,
    rollConcentration,
    concentrationMod,
  };
}
