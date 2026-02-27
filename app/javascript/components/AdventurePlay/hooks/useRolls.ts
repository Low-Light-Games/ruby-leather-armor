import { useState, useCallback } from 'react';
import type { AttributeType, AdventureSheet, DerivedStats } from '../../../types';
import type { RollResultDisplay } from '../../RollResultModal';
import type { DamageRollResult } from '../../../rules/dice';
import { formatMod, ABILITY_ABBR } from '../../../utils/formatting';
import { rollD20 } from '../../../rules/dice';
import { rollWeaponDamage as calcWeaponDamage, rollSpellDamage as calcSpellDamage } from '../../../rules/damage';
import { getSpellById } from '../../../rules/pathfinder_spells';

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
  };
}
