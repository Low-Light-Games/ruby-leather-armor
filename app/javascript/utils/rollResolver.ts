import type { RollRequest, DerivedStats, DerivedSkill } from '../types'
import { formatMod, ABILITY_ABBR } from './formatting'

export type ResolvedRoll =
  | {
      kind: 'd20'
      modifier: number
      label: string
      modifierLabel: string
    }
  | {
      kind: 'spell_damage'
      spellId: string
      label: string
    }
  | {
      kind: 'weapon_damage'
      itemId: string
      label: string
    }
  | {
      kind: 'unarmed_damage'
      label: string
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
    return resolveAttack(skillLower, ds, req)
  }

  if (rollType === 'ability_check' || rollType === 'ability') {
    return resolveAbilityCheck(skillLower, ds)
  }

  if (rollType === 'initiative') {
    return { kind: 'd20', modifier: ds.initiative, label: 'Initiative', modifierLabel: `Init ${formatMod(ds.initiative)}` }
  }

  if (rollType === 'damage_roll' || rollType === 'damage') {
    return resolveDamage(req)
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
    kind: 'd20',
    modifier: skill.total,
    label: `${skill.name} Check`,
    modifierLabel: `Skill ${formatMod(skill.total)}`,
  }
}

function resolveSave(skillLower: string, ds: DerivedStats): ResolvedRoll | null {
  const entry = SAVE_MAP[skillLower]
  if (!entry) return null

  const mod = ds[entry.key]
  return {
    kind: 'd20',
    modifier: mod,
    label: entry.label,
    modifierLabel: `${entry.label.split(' ')[0]} ${formatMod(mod)}`
  }
}

function resolveAttack(_skillLower: string, ds: DerivedStats, req?: RollRequest): ResolvedRoll | null {
  const mode = req?.attack_mode?.toLowerCase()

  if (mode === 'ranged' || mode === 'ranged_touch') {
    return {
      kind: 'd20',
      modifier: ds.ranged_attack,
      label: mode === 'ranged_touch' ? 'Ranged Touch Attack' : 'Ranged Attack',
      modifierLabel: `BAB ${formatMod(ds.bab)} + DEX ${formatMod(ds.mods.dexterity)}`,
    }
  }

  if (mode === 'melee' || mode === 'melee_touch') {
    return {
      kind: 'd20',
      modifier: ds.melee_attack,
      label: mode === 'melee_touch' ? 'Melee Touch Attack' : 'Melee Attack',
      modifierLabel: `BAB ${formatMod(ds.bab)} + STR ${formatMod(ds.mods.strength)}`,
    }
  }

  return {
    kind: 'd20',
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
  return { kind: 'd20', modifier: mod, label: `${abbr} Check`, modifierLabel: `${abbr} ${formatMod(mod)}` }
}

function resolveDamage(req: RollRequest): ResolvedRoll | null {
  const sourceType = req.source_type?.toLowerCase()

  if (sourceType === 'spell' && req.source_id) {
    return { kind: 'spell_damage', spellId: req.source_id, label: req.description }
  }

  if (sourceType === 'weapon' && req.source_id) {
    return { kind: 'weapon_damage', itemId: req.source_id, label: req.description }
  }

  if (sourceType === 'unarmed') {
    return { kind: 'unarmed_damage', label: req.description }
  }

  return null
}
