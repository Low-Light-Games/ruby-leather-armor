import type { RollRequest, DerivedStats, DerivedSkill } from '../types'
import { formatMod, ABILITY_ABBR } from './formatting'

export interface ResolvedRoll {
  modifier: number
  label: string
  modifierLabel: string
}

const SAVE_MAP: Record<string, { key: keyof Pick<DerivedStats, 'fort' | 'ref' | 'will'>; label: string }> = {
  fortitude: { key: 'fort', label: 'Fortitude Save' },
  fort: { key: 'fort', label: 'Fortitude Save' },
  constitution: { key: 'fort', label: 'Fortitude Save' }, // AI sometimes uses "Constitution" for Fortitude saves
  con: { key: 'fort', label: 'Fortitude Save' },
  reflex: { key: 'ref', label: 'Reflex Save' },
  ref: { key: 'ref', label: 'Reflex Save' },
  dexterity: { key: 'ref', label: 'Reflex Save' }, // AI sometimes uses "Dexterity" for Reflex saves
  dex: { key: 'ref', label: 'Reflex Save' },
  will: { key: 'will', label: 'Will Save' },
  wisdom: { key: 'will', label: 'Will Save' }, // AI sometimes uses "Wisdom" for Will saves
  wis: { key: 'will', label: 'Will Save' },
}

const ABILITY_MAP: Record<string, string> = {
  strength: 'strength', str: 'strength',
  dexterity: 'dexterity', dex: 'dexterity',
  constitution: 'constitution', con: 'constitution',
  intelligence: 'intelligence', int: 'intelligence',
  wisdom: 'wisdom', wis: 'wisdom',
  charisma: 'charisma', cha: 'charisma',
}

/**
 * Maps an AI-generated roll request to a concrete character ability with
 * the correct modifier. Returns null if the roll doesn't match any known
 * ability on the character sheet (hallucination).
 */
export function resolveRollRequest(req: RollRequest, ds: DerivedStats): ResolvedRoll | null {
  const skillName = (req.skill ?? '').trim()
  const skillLower = skillName.toLowerCase()
  const rollType = (req.type ?? '').toLowerCase()

  if (rollType === 'skill_check' || rollType === 'skill') {
    return resolveSkillCheck(skillLower, skillName, ds)
  }

  if (rollType === 'saving_throw' || rollType === 'save') {
    return resolveSave(skillLower, ds)
  }

  if (rollType === 'attack_roll' || rollType === 'attack') {
    return resolveAttack(skillLower, ds)
  }

  if (rollType === 'ability_check' || rollType === 'ability') {
    return resolveAbilityCheck(skillLower, ds)
  }

  if (rollType === 'initiative') {
    return { modifier: ds.initiative, label: 'Initiative', modifierLabel: `Init ${formatMod(ds.initiative)}` }
  }

  if (rollType === 'damage_roll' || rollType === 'damage') {
    return null
  }

  // Fallback: try skill match, then save, then ability
  return resolveSkillCheck(skillLower, skillName, ds)
    ?? resolveSave(skillLower, ds)
    ?? resolveAbilityCheck(skillLower, ds)
}

function resolveSkillCheck(skillLower: string, skillName: string, ds: DerivedStats): ResolvedRoll | null {
  if (!ds.skills?.length) return null

  const skill = ds.skills.find(
    (s: DerivedSkill) => s.name.toLowerCase() === skillLower
  )
  if (!skill) return null

  return {
    modifier: skill.total,
    label: `${skill.name} Check`,
    modifierLabel: `Skill ${formatMod(skill.total)}`,
  }
}

function resolveSave(skillLower: string, ds: DerivedStats): ResolvedRoll | null {
  const entry = SAVE_MAP[skillLower]
  if (!entry) return null

  const mod = ds[entry.key]
  return { modifier: mod, label: entry.label, modifierLabel: `${entry.label.split(' ')[0]} ${formatMod(mod)}` }
}

function resolveAttack(skillLower: string, ds: DerivedStats): ResolvedRoll | null {
  if (skillLower.includes('ranged')) {
    return {
      modifier: ds.ranged_attack,
      label: 'Ranged Attack',
      modifierLabel: `BAB ${formatMod(ds.bab)} + DEX ${formatMod(ds.mods.dexterity)}`,
    }
  }
  return {
    modifier: ds.melee_attack,
    label: 'Melee Attack',
    modifierLabel: `BAB ${formatMod(ds.bab)} + STR ${formatMod(ds.mods.strength)}`,
  }
}

function resolveAbilityCheck(skillLower: string, ds: DerivedStats): ResolvedRoll | null {
  const abilityKey = ABILITY_MAP[skillLower]
  if (!abilityKey) return null

  const mod = ds.mods[abilityKey] ?? 0
  const abbr = ABILITY_ABBR[abilityKey as keyof typeof ABILITY_ABBR] ?? abilityKey.slice(0, 3).toUpperCase()
  return { modifier: mod, label: `${abbr} Check`, modifierLabel: `${abbr} ${formatMod(mod)}` }
}
