export type BABProgression = 'full' | '3/4' | '1/2';

export interface ClassDefinition {
  id: string;
  name: string;
  hitDie: number;
  bab: BABProgression;
  goodSaves: ('fort' | 'ref' | 'will')[];
}

export const PATHFINDER_CLASSES: ClassDefinition[] = [
  { id: 'barbarian', name: 'Barbarian', hitDie: 12, bab: 'full',  goodSaves: ['fort'] },
  { id: 'bard',      name: 'Bard',      hitDie: 8,  bab: '3/4',  goodSaves: ['ref', 'will'] },
  { id: 'cleric',    name: 'Cleric',    hitDie: 8,  bab: '3/4',  goodSaves: ['fort', 'will'] },
  { id: 'druid',     name: 'Druid',     hitDie: 8,  bab: '3/4',  goodSaves: ['fort', 'will'] },
  { id: 'fighter',   name: 'Fighter',   hitDie: 10, bab: 'full',  goodSaves: ['fort'] },
  { id: 'monk',      name: 'Monk',      hitDie: 8,  bab: '3/4',  goodSaves: ['fort', 'ref', 'will'] },
  { id: 'paladin',   name: 'Paladin',   hitDie: 10, bab: 'full',  goodSaves: ['fort', 'will'] },
  { id: 'ranger',    name: 'Ranger',    hitDie: 10, bab: 'full',  goodSaves: ['fort', 'ref'] },
  { id: 'rogue',     name: 'Rogue',     hitDie: 8,  bab: '3/4',  goodSaves: ['ref'] },
  { id: 'sorcerer',  name: 'Sorcerer',  hitDie: 6,  bab: '1/2',  goodSaves: ['will'] },
  { id: 'wizard',    name: 'Wizard',    hitDie: 6,  bab: '1/2',  goodSaves: ['will'] },
];

export function getClassById(id: string): ClassDefinition | undefined {
  return PATHFINDER_CLASSES.find(c => c.id === id);
}
