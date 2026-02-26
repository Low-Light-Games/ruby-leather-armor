import { useState, useCallback } from 'react';
import type { AttributeType, DerivedStats } from '../../../types';
import type { RollResultDisplay } from '../../RollResultModal';
import { formatMod, ABILITY_ABBR } from '../../../utils/formatting';
import { rollD20 } from '../../../rules/dice';

interface UseRollsResult {
  rollDisplay: RollResultDisplay | null;
  clearRoll: () => void;
  rollMeleeAttack: () => void;
  rollRangedAttack: () => void;
  rollFort: () => void;
  rollRef: () => void;
  rollWill: () => void;
  rollInitiative: () => void;
  rollAbility: (attr: AttributeType) => void;
  rollSkill: (skillName: string, total: number) => void;
}

export function useRolls(ds: DerivedStats | null): UseRollsResult {
  const [rollDisplay, setRollDisplay] = useState<RollResultDisplay | null>(null);

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

  return {
    rollDisplay,
    clearRoll: () => setRollDisplay(null),
    rollMeleeAttack,
    rollRangedAttack,
    rollFort,
    rollRef,
    rollWill,
    rollInitiative,
    rollAbility,
    rollSkill,
  };
}
