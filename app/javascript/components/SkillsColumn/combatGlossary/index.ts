import type { CombatGlossaryKey, CombatGlossaryEntry } from './types';
import { AC_GLOSSARY } from './entries/ac';
import { TOUCH_AC_GLOSSARY } from './entries/touchAc';
import { FLAT_FOOTED_GLOSSARY } from './entries/flatFooted';
import { BAB_GLOSSARY } from './entries/bab';
import { INITIATIVE_GLOSSARY } from './entries/initiative';
import { SPEED_GLOSSARY } from './entries/speed';
import { CMB_GLOSSARY } from './entries/cmb';
import { CMD_GLOSSARY } from './entries/cmd';
import { FORT_GLOSSARY } from './entries/fort';
import { REF_GLOSSARY } from './entries/ref';
import { WILL_GLOSSARY } from './entries/will';
import { HP_BONUS_GLOSSARY } from './entries/hpBonus';
import { ARMOR_BONUS_GLOSSARY } from './entries/armorBonus';
import { SHIELD_BONUS_GLOSSARY } from './entries/shieldBonus';
import { ACP_GLOSSARY } from './entries/acp';
import { ARCANE_SPELL_FAILURE_GLOSSARY } from './entries/arcaneSpellFailure';
import { ENCUMBRANCE_GLOSSARY } from './entries/encumbrance';

export type { CombatGlossaryKey, CombatGlossaryEntry } from './types';

/** Lookup table for modal content — each key maps to a single glossary module. */
export const COMBAT_GLOSSARY_BY_KEY: Record<CombatGlossaryKey, CombatGlossaryEntry> = {
  ac: AC_GLOSSARY,
  touchAc: TOUCH_AC_GLOSSARY,
  flatFooted: FLAT_FOOTED_GLOSSARY,
  bab: BAB_GLOSSARY,
  initiative: INITIATIVE_GLOSSARY,
  speed: SPEED_GLOSSARY,
  cmb: CMB_GLOSSARY,
  cmd: CMD_GLOSSARY,
  fort: FORT_GLOSSARY,
  ref: REF_GLOSSARY,
  will: WILL_GLOSSARY,
  hpBonus: HP_BONUS_GLOSSARY,
  armorBonus: ARMOR_BONUS_GLOSSARY,
  shieldBonus: SHIELD_BONUS_GLOSSARY,
  acp: ACP_GLOSSARY,
  arcaneSpellFailure: ARCANE_SPELL_FAILURE_GLOSSARY,
  encumbrance: ENCUMBRANCE_GLOSSARY,
};

export function getCombatGlossaryEntry(key: CombatGlossaryKey): CombatGlossaryEntry {
  return COMBAT_GLOSSARY_BY_KEY[key];
}
