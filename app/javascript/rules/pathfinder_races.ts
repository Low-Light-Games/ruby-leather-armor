import { AttributeType } from '../types';

export interface RaceDefinition {
  id: string;
  name: string;
  size: 'Small' | 'Medium';
  speed: number;
  /** Fixed ability score modifiers applied automatically */
  fixedModifiers: Partial<Record<AttributeType, number>>;
  /** Number of flexible +2 bonuses the player may assign (0 for most races) */
  flexibleBonusCount: number;
  /** Unconditional racial skill bonuses */
  skillBonuses: { skill: string; bonus: number }[];
}

export const PATHFINDER_RACES: RaceDefinition[] = [
  {
    id: 'human',
    name: 'Human',
    size: 'Medium',
    speed: 30,
    fixedModifiers: {},
    flexibleBonusCount: 1,
    skillBonuses: [],
  },
  {
    id: 'elf',
    name: 'Elf',
    size: 'Medium',
    speed: 30,
    fixedModifiers: { dexterity: 2, intelligence: 2, constitution: -2 },
    flexibleBonusCount: 0,
    skillBonuses: [{ skill: 'Perception', bonus: 2 }],
  },
  {
    id: 'dwarf',
    name: 'Dwarf',
    size: 'Medium',
    speed: 20,
    fixedModifiers: { constitution: 2, wisdom: 2, charisma: -2 },
    flexibleBonusCount: 0,
    skillBonuses: [],
  },
  {
    id: 'halfling',
    name: 'Halfling',
    size: 'Small',
    speed: 20,
    fixedModifiers: { dexterity: 2, charisma: 2, strength: -2 },
    flexibleBonusCount: 0,
    skillBonuses: [
      { skill: 'Perception', bonus: 2 },
      { skill: 'Acrobatics', bonus: 2 },
      { skill: 'Climb', bonus: 2 },
    ],
  },
  {
    id: 'gnome',
    name: 'Gnome',
    size: 'Small',
    speed: 20,
    fixedModifiers: { constitution: 2, charisma: 2, strength: -2 },
    flexibleBonusCount: 0,
    skillBonuses: [{ skill: 'Perception', bonus: 2 }],
  },
  {
    id: 'half_elf',
    name: 'Half-Elf',
    size: 'Medium',
    speed: 30,
    fixedModifiers: {},
    flexibleBonusCount: 1,
    skillBonuses: [{ skill: 'Perception', bonus: 2 }],
  },
  {
    id: 'half_orc',
    name: 'Half-Orc',
    size: 'Medium',
    speed: 30,
    fixedModifiers: {},
    flexibleBonusCount: 1,
    skillBonuses: [{ skill: 'Intimidate', bonus: 2 }],
  },
];

/**
 * Look up a race definition by its id.
 */
export function getRaceById(id: string): RaceDefinition | undefined {
  return PATHFINDER_RACES.find(r => r.id === id);
}

/**
 * Compute the total racial ability modifiers for a given race,
 * including any flexible bonus assigned to `flexibleAttribute`.
 */
export function computeRacialModifiers(
  race: RaceDefinition | undefined,
  flexibleAttribute: AttributeType | null,
): Record<AttributeType, number> {
  const mods: Record<AttributeType, number> = {
    strength: 0,
    dexterity: 0,
    constitution: 0,
    intelligence: 0,
    wisdom: 0,
    charisma: 0,
  };

  if (!race) return mods;

  // Apply fixed modifiers
  for (const [attr, val] of Object.entries(race.fixedModifiers)) {
    mods[attr as AttributeType] = val as number;
  }

  // Apply flexible bonus
  if (race.flexibleBonusCount > 0 && flexibleAttribute) {
    mods[flexibleAttribute] += 2;
  }

  return mods;
}
