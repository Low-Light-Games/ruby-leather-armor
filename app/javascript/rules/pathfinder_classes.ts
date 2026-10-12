export type BABProgression = 'full' | '3/4' | '1/2';
export type CastingType = 'prepared' | 'spontaneous';

/**
 * How a class acquires and manages spells:
 * - `none`           — non-caster (barbarian, fighter, monk, rogue)
 * - `spontaneous`    — limited spells known, cast any known freely (sorcerer, bard)
 * - `spellbook`      — wizard: spellbook of learned spells, prepare a subset daily
 * - `prepared_list`  — cleric/druid/paladin/ranger: know full class list, prepare daily
 */
export type CastingStyle = 'none' | 'spontaneous' | 'spellbook' | 'prepared_list';

export interface SpellcastingInfo {
  type: CastingType;
  ability: 'intelligence' | 'wisdom' | 'charisma';
  // Minimum character level per spell level (index 0 = cantrips); null = never gained.
  progression: (number | null)[];
  style: CastingStyle;
  // Spontaneous casters only: spellsKnown[charLevel - 1][spellLevel].
  spellsKnown?: number[][];
}

export interface ClassDefinition {
  id: string;
  name: string;
  hitDie: number;
  bab: BABProgression;
  goodSaves: ('fort' | 'ref' | 'will')[];
  // Per level, before the Int modifier.
  skillPointsBase: number;
  spellcasting?: SpellcastingInfo;
}

/* prettier-ignore */
const SORCERER_SPELLS_KNOWN: number[][] = [
  //  0  1  2  3  4  5  6  7  8  9   ← spell level
  [4, 2],                              // Lv  1
  [5, 2],                              // Lv  2
  [5, 3],                              // Lv  3
  [6, 3, 1],                           // Lv  4
  [6, 4, 2],                           // Lv  5
  [7, 4, 2, 1],                        // Lv  6
  [7, 5, 3, 2],                        // Lv  7
  [8, 5, 3, 2, 1],                     // Lv  8
  [8, 5, 4, 3, 2],                     // Lv  9
  [9, 5, 4, 3, 2, 1],                  // Lv 10
  [9, 5, 5, 4, 3, 2],                  // Lv 11
  [9, 5, 5, 4, 3, 2, 1],              // Lv 12
  [9, 5, 5, 4, 4, 3, 2],              // Lv 13
  [9, 5, 5, 4, 4, 3, 2, 1],           // Lv 14
  [9, 5, 5, 4, 4, 4, 3, 2],           // Lv 15
  [9, 5, 5, 4, 4, 4, 3, 2, 1],        // Lv 16
  [9, 5, 5, 4, 4, 4, 3, 3, 2],        // Lv 17
  [9, 5, 5, 4, 4, 4, 3, 3, 2, 1],     // Lv 18
  [9, 5, 5, 4, 4, 4, 3, 3, 3, 2],     // Lv 19
  [9, 5, 5, 4, 4, 4, 3, 3, 3, 3],     // Lv 20
];

/* prettier-ignore */
const BARD_SPELLS_KNOWN: number[][] = [
  //  0  1  2  3  4  5  6   ← spell level
  [4, 2],                    // Lv  1
  [5, 3],                    // Lv  2
  [6, 4],                    // Lv  3
  [6, 4, 2],                 // Lv  4
  [6, 4, 3],                 // Lv  5
  [6, 4, 3],                 // Lv  6
  [6, 5, 4, 2],              // Lv  7
  [6, 5, 4, 3],              // Lv  8
  [6, 5, 4, 3],              // Lv  9
  [6, 5, 4, 4, 2],           // Lv 10
  [6, 6, 5, 4, 3],           // Lv 11
  [6, 6, 5, 4, 3],           // Lv 12
  [6, 6, 5, 4, 4, 2],        // Lv 13
  [6, 6, 5, 4, 4, 3],        // Lv 14
  [6, 6, 5, 5, 4, 3],        // Lv 15
  [6, 6, 5, 5, 4, 4, 2],     // Lv 16
  [6, 6, 5, 5, 4, 4, 3],     // Lv 17
  [6, 6, 5, 5, 5, 4, 3],     // Lv 18
  [6, 6, 5, 5, 5, 5, 4],     // Lv 19
  [6, 6, 5, 5, 5, 5, 5],     // Lv 20
];

export const PATHFINDER_CLASSES: ClassDefinition[] = [
  { id: 'barbarian', name: 'Barbarian', hitDie: 12, bab: 'full', goodSaves: ['fort'], skillPointsBase: 4 },
  {
    id: 'bard', name: 'Bard', hitDie: 8, bab: '3/4', goodSaves: ['ref', 'will'], skillPointsBase: 6,
    spellcasting: {
      type: 'spontaneous', ability: 'charisma', style: 'spontaneous',
      progression: [1, 1, 4, 7, 10, 13, 16],
      spellsKnown: BARD_SPELLS_KNOWN,
    },
  },
  {
    id: 'cleric', name: 'Cleric', hitDie: 8, bab: '3/4', goodSaves: ['fort', 'will'], skillPointsBase: 2,
    spellcasting: {
      type: 'prepared', ability: 'wisdom', style: 'prepared_list',
      progression: [1, 1, 3, 5, 7, 9, 11, 13, 15, 17],
    },
  },
  {
    id: 'druid', name: 'Druid', hitDie: 8, bab: '3/4', goodSaves: ['fort', 'will'], skillPointsBase: 4,
    spellcasting: {
      type: 'prepared', ability: 'wisdom', style: 'prepared_list',
      progression: [1, 1, 3, 5, 7, 9, 11, 13, 15, 17],
    },
  },
  { id: 'fighter', name: 'Fighter', hitDie: 10, bab: 'full', goodSaves: ['fort'], skillPointsBase: 2 },
  { id: 'monk', name: 'Monk', hitDie: 8, bab: '3/4', goodSaves: ['fort', 'ref', 'will'], skillPointsBase: 4 },
  {
    id: 'paladin', name: 'Paladin', hitDie: 10, bab: 'full', goodSaves: ['fort', 'will'], skillPointsBase: 2,
    spellcasting: {
      type: 'prepared', ability: 'charisma', style: 'prepared_list',
      progression: [null, 4, 7, 10, 13],
    },
  },
  {
    id: 'ranger', name: 'Ranger', hitDie: 10, bab: 'full', goodSaves: ['fort', 'ref'], skillPointsBase: 6,
    spellcasting: {
      type: 'prepared', ability: 'wisdom', style: 'prepared_list',
      progression: [null, 4, 7, 10, 13],
    },
  },
  { id: 'rogue', name: 'Rogue', hitDie: 8, bab: '3/4', goodSaves: ['ref'], skillPointsBase: 8 },
  {
    id: 'sorcerer', name: 'Sorcerer', hitDie: 6, bab: '1/2', goodSaves: ['will'], skillPointsBase: 2,
    spellcasting: {
      type: 'spontaneous', ability: 'charisma', style: 'spontaneous',
      progression: [1, 1, 4, 6, 8, 10, 12, 14, 16, 18],
      spellsKnown: SORCERER_SPELLS_KNOWN,
    },
  },
  {
    id: 'wizard', name: 'Wizard', hitDie: 6, bab: '1/2', goodSaves: ['will'], skillPointsBase: 2,
    spellcasting: {
      type: 'prepared', ability: 'intelligence', style: 'spellbook',
      progression: [1, 1, 3, 5, 7, 9, 11, 13, 15, 17],
    },
  },
];

export function getClassById(id: string): ClassDefinition | undefined {
  return PATHFINDER_CLASSES.find(c => c.id === id);
}
