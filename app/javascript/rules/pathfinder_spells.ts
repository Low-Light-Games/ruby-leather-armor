import { SpellDefinition, SpellSchool } from './pathfinder_spells_types';
import { getClassById, CastingStyle } from './pathfinder_classes';
import { abilityModifier } from './pathfinder_skills';

export type { CastingStyle } from './pathfinder_classes';
export type { SpellDefinition, SpellSchool } from './pathfinder_spells_types';
export type { SpellComponent, SpellEffect } from './pathfinder_spells_types';

let ALL_SPELLS: SpellDefinition[] = [];

export function setSpellDefinitions(spells: SpellDefinition[]): void {
  ALL_SPELLS = spells;
}

export function getAllSpells(): SpellDefinition[] {
  return ALL_SPELLS;
}

export function getSpellById(id: string): SpellDefinition | undefined {
  return ALL_SPELLS.find(s => s.id === id);
}

export function getSpellsBySchool(school: SpellSchool): SpellDefinition[] {
  return ALL_SPELLS.filter(s => s.school === school);
}

export function getSpellsByClassAndLevel(className: string, level: number): SpellDefinition[] {
  const key = className.toLowerCase();
  return ALL_SPELLS.filter(s => s.classLevels[key] === level);
}

export function getCantrips(className: string): SpellDefinition[] {
  return getSpellsByClassAndLevel(className, 0);
}

export function getLevel1Spells(className: string): SpellDefinition[] {
  return getSpellsByClassAndLevel(className, 1);
}

export function getSpellsForClass(className: string, maxLevel: number = 1): SpellDefinition[] {
  const key = className.toLowerCase();
  return ALL_SPELLS.filter(s => {
    const spellLevel = s.classLevels[key];
    return spellLevel !== undefined && spellLevel <= maxLevel;
  });
}

export function isSpellcaster(classId: string | null): boolean {
  if (!classId) return false;
  const cls = getClassById(classId);
  return !!cls?.spellcasting;
}

export function castingStartLevel(classId: string | null): number | null {
  if (!classId) return null;
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return null;

  for (const minCharLevel of cls.spellcasting.progression) {
    if (minCharLevel !== null) return minCharLevel;
  }
  return null;
}

export function maxSpellLevelForClass(classId: string | null, charLevel: number): number {
  if (!classId) return -1;
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return -1;

  let highestSpellLevel = -1;
  for (let spellLevel = 0; spellLevel < cls.spellcasting.progression.length; spellLevel++) {
    const minCharLevel = cls.spellcasting.progression[spellLevel];
    if (minCharLevel !== null && charLevel >= minCharLevel) {
      highestSpellLevel = spellLevel;
    }
  }
  return highestSpellLevel;
}

export type SpellEligibilityStatus = 'available' | 'too_high_level' | 'wrong_class' | 'no_casting';

export interface SpellEligibility {
  status: SpellEligibilityStatus;
  spellLevel: number | undefined;
  reason?: string;
}

export function checkSpellEligibility(
  classId: string | null,
  charLevel: number,
  spell: SpellDefinition,
): SpellEligibility {
  if (!classId) {
    // Without a class there is nothing to validate against, so the list stays browsable.
    const firstListedSpellLevel = Object.values(spell.classLevels)[0];
    return { status: 'available', spellLevel: firstListedSpellLevel };
  }

  const cls = getClassById(classId);
  if (!cls) {
    return { status: 'available', spellLevel: undefined };
  }

  if (!cls.spellcasting) {
    return {
      status: 'no_casting',
      spellLevel: undefined,
      reason: `${cls.name} cannot cast spells`,
    };
  }

  const spellLevel = spell.classLevels[classId.toLowerCase()];
  if (spellLevel === undefined) {
    return {
      status: 'wrong_class',
      spellLevel: undefined,
      reason: `Not on the ${cls.name} spell list`,
    };
  }

  if (spellLevel > maxSpellLevelForClass(classId, charLevel)) {
    const minCharLevel = cls.spellcasting.progression[spellLevel];
    return {
      status: 'too_high_level',
      spellLevel,
      reason: minCharLevel !== null
        ? `Requires ${cls.name} level ${minCharLevel} (spell level ${spellLevel})`
        : `Spell level ${spellLevel} not accessible yet`,
    };
  }

  return { status: 'available', spellLevel };
}

export function canSelectSpell(eligibility: SpellEligibility): boolean {
  return eligibility.status === 'available';
}

export function getCastingStyle(classId: string | null): CastingStyle {
  if (!classId) return 'none';
  const cls = getClassById(classId);
  return cls?.spellcasting?.style ?? 'none';
}

export function maxKnownSpells(
  classId: string | null,
  charLevel: number,
  spellLevel: number,
): number {
  if (!classId) return 0;
  const cls = getClassById(classId);
  const table = cls?.spellcasting?.spellsKnown;
  if (!table) return 0;

  const row = table[Math.min(charLevel, table.length) - 1];
  if (!row) return 0;
  return row[spellLevel] ?? 0;
}

const WIZARD_STARTING_SPELLBOOK_SLOTS = 3;
const WIZARD_SPELLBOOK_SLOTS_PER_LEVEL_UP = 2;

// Every wizard cantrip is in the spellbook, hence Infinity at level 0. Level-up slots are
// granted to every accessible spell level until the UI tracks where each one was spent.
export function wizardSpellbookSlots(
  charLevel: number,
  intScore: number,
  spellLevel: number,
): number {
  if (spellLevel === 0) return Infinity;

  const startingSlots = Math.max(WIZARD_STARTING_SPELLBOOK_SLOTS + abilityModifier(intScore), 1);
  const levelUpSlots = WIZARD_SPELLBOOK_SLOTS_PER_LEVEL_UP * Math.max(charLevel - 1, 0);
  return startingSlots + levelUpSlots;
}

function spellSelectionLimit(
  style: CastingStyle,
  classId: string,
  charLevel: number,
  intScore: number,
  spellLevel: number,
): number {
  return style === 'spontaneous'
    ? maxKnownSpells(classId, charLevel, spellLevel)
    : wizardSpellbookSlots(charLevel, intScore, spellLevel);
}

export interface SpellSlotSummary {
  spellLevel: number;
  label: string;
  limit: number;
  used: number;
  remaining: number;
}

const SPELL_LEVEL_LABELS: Record<number, string> = {
  0: 'Cantrips',
  1: '1st Level',
  2: '2nd Level',
  3: '3rd Level',
  4: '4th Level',
  5: '5th Level',
  6: '6th Level',
  7: '7th Level',
  8: '8th Level',
  9: '9th Level',
};

export function computeSpellSlots(
  classId: string | null,
  charLevel: number,
  intScore: number,
  selectedSpellIds: string[],
): SpellSlotSummary[] {
  if (!classId) return [];
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return [];

  const style = cls.spellcasting.style;
  if (style === 'none' || style === 'prepared_list') return [];

  const highestSpellLevel = maxSpellLevelForClass(classId, charLevel);
  if (highestSpellLevel < 0) return [];

  const selectedCountBySpellLevel: Record<number, number> = {};
  for (const id of selectedSpellIds) {
    const spell = getSpellById(id);
    if (!spell) continue;
    const spellLevel = spell.classLevels[classId.toLowerCase()];
    if (spellLevel !== undefined) {
      selectedCountBySpellLevel[spellLevel] = (selectedCountBySpellLevel[spellLevel] || 0) + 1;
    }
  }

  const result: SpellSlotSummary[] = [];
  for (let spellLevel = 0; spellLevel <= highestSpellLevel; spellLevel++) {
    const used = selectedCountBySpellLevel[spellLevel] || 0;
    const limit = spellSelectionLimit(style, classId, charLevel, intScore, spellLevel);
    if (limit === 0 && used === 0) continue;

    result.push({
      spellLevel,
      label: SPELL_LEVEL_LABELS[spellLevel] ?? `Level ${spellLevel}`,
      limit,
      used,
      remaining: limit === Infinity ? Infinity : Math.max(limit - used, 0),
    });
  }

  return result;
}

export function hasSlotForSpell(
  classId: string | null,
  charLevel: number,
  intScore: number,
  spell: SpellDefinition,
  selectedSpellIds: string[],
): boolean {
  if (!classId) return true;
  const cls = getClassById(classId);
  if (!cls?.spellcasting) return false;

  const style = cls.spellcasting.style;
  if (style === 'prepared_list') return true;
  if (style === 'none') return false;

  const spellLevel = spell.classLevels[classId.toLowerCase()];
  if (spellLevel === undefined) return false;

  let selectedAtSpellLevel = 0;
  for (const id of selectedSpellIds) {
    const selected = getSpellById(id);
    if (selected && selected.classLevels[classId.toLowerCase()] === spellLevel) selectedAtSpellLevel++;
  }

  return selectedAtSpellLevel < spellSelectionLimit(style, classId, charLevel, intScore, spellLevel);
}
