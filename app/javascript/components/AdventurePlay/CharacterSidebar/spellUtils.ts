import type { SpellDefinition } from '../../../rules/pathfinder_spells_types'

export function getSpellLevelForClass(
  spell: SpellDefinition,
  characterClass: string | undefined | null,
): string | number {
  if (characterClass) {
    return spell.classLevels[characterClass.toLowerCase()] ?? '?'
  }
  return Object.values(spell.classLevels)[0] ?? '?'
}
