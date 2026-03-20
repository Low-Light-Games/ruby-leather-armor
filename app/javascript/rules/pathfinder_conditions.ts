export interface ConditionDef {
  label: string
  description: string
  color: string
}

export const CONDITIONS: Record<string, ConditionDef> = {
  fatigued: {
    label: 'Fatigued',
    description: '-2 STR, -2 DEX. Cannot run or charge.',
    color: 'amber',
  },
  exhausted: {
    label: 'Exhausted',
    description: '-6 STR, -6 DEX. Half speed. Cannot run or charge.',
    color: 'red',
  },
  shaken: {
    label: 'Shaken',
    description: '-2 on attack rolls, saving throws, skill checks, and ability checks.',
    color: 'amber',
  },
  frightened: {
    label: 'Frightened',
    description: '-2 on attack rolls, saves, skill checks, ability checks. Must flee.',
    color: 'orange',
  },
  panicked: {
    label: 'Panicked',
    description: '-2 on attack rolls, saves, skill checks, ability checks. Must flee, drops held items.',
    color: 'red',
  },
  sickened: {
    label: 'Sickened',
    description: '-2 on attack rolls, weapon damage, saves, skill checks, and ability checks.',
    color: 'green',
  },
  nauseated: {
    label: 'Nauseated',
    description: 'Can only take a single move action per turn. Cannot attack or cast spells.',
    color: 'green',
  },
  entangled: {
    label: 'Entangled',
    description: '-2 on attack rolls, -4 DEX.',
    color: 'amber',
  },
  prone: {
    label: 'Prone',
    description: '-4 on melee attack rolls. -4 AC vs melee, +4 AC vs ranged.',
    color: 'slate',
  },
  blinded: {
    label: 'Blinded',
    description: '-2 AC, loses Dex bonus to AC. All opponents have total concealment.',
    color: 'slate',
  },
  staggered: {
    label: 'Staggered',
    description: 'Can only take a single move or standard action per turn (not both).',
    color: 'orange',
  },
  paralyzed: {
    label: 'Paralyzed',
    description: 'Cannot move or act. STR and DEX effectively 0. Loses Dex bonus to AC.',
    color: 'red',
  },
  stunned: {
    label: 'Stunned',
    description: 'Cannot act, -2 AC, loses Dex bonus to AC.',
    color: 'red',
  },
  dazed: {
    label: 'Dazed',
    description: 'Cannot act. Can take no actions but has no penalty to AC.',
    color: 'orange',
  },
  poisoned: {
    label: 'Poisoned',
    description: 'Affected by poison. Effects vary by the specific poison.',
    color: 'green',
  },
  grappled: {
    label: 'Grappled',
    description: '-2 on attack rolls, -4 DEX. Cannot move. Loses Dex to AC vs non-grappler.',
    color: 'orange',
  },
}

export function getCondition(name: string): ConditionDef | undefined {
  return CONDITIONS[name]
}
