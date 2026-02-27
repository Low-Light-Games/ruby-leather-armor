/**
 * Damage calculation for weapons and spells.
 * Accounts for ability modifiers, weapon properties, and feat effects.
 * Pure game mechanics — Open Game Content.
 */

import type { DamageRollResult, ParsedDice } from './dice'
import { parseDiceNotation, rollParsedDice } from './dice'
import type { ItemDefinition } from './pathfinder_items_types'
import type { SpellDefinition, SpellEffect } from './pathfinder_spells_types'
import type { FeatDefinition } from './pathfinder_feats_types'
import type { AdventureSheet, DerivedStats } from '../types'
import { getItemById } from './pathfinder_items'
import { getFeatById } from './pathfinder_feats'

// ── Property helpers ─────────────────────────────────────────

function prop(item: ItemDefinition, key: string): unknown {
  return item.properties?.[key]
}

export function isFinesse(item: ItemDefinition): boolean {
  return !!prop(item, 'finesse') || !!prop(item, 'light')
}

export function isTwoHanded(item: ItemDefinition): boolean {
  return !!prop(item, 'twoHanded')
}

export function isLight(item: ItemDefinition): boolean {
  return !!prop(item, 'light')
}

// ── Feat helpers ─────────────────────────────────────────────

function loadFeats(sheet: AdventureSheet): FeatDefinition[] {
  const ids = sheet.details?.feats ?? []
  return ids.map(id => getFeatById(id)).filter((f): f is FeatDefinition => !!f)
}

function hasReplaceModifier(feats: FeatDefinition[]): boolean {
  return feats.some(f =>
    f.effects.some(e => e.type === 'replace_modifier' && e.to === 'DEX')
  )
}

// ── Weapon attack modifier ───────────────────────────────────

export function getWeaponAttackMod(
  item: ItemDefinition,
  ds: DerivedStats,
  feats: FeatDefinition[],
): { total: number; label: string } {
  if (item.weaponType === 'ranged') {
    return { total: ds.ranged_attack, label: `BAB +${ds.bab} + DEX ${formatMod(ds.mods.dexterity)}` }
  }
  if (isFinesse(item) && hasReplaceModifier(feats)) {
    const total = ds.bab + ds.mods.dexterity + (ds.feat_stat_bonuses?.melee_attack ?? 0)
    return { total, label: `BAB +${ds.bab} + DEX ${formatMod(ds.mods.dexterity)} (Finesse)` }
  }
  return { total: ds.melee_attack, label: `BAB +${ds.bab} + STR ${formatMod(ds.mods.strength)}` }
}

// ── Weapon damage roll ───────────────────────────────────────

export function rollWeaponDamage(
  itemId: string,
  sheet: AdventureSheet,
  ds: DerivedStats,
): DamageRollResult | null {
  const item = getItemById(itemId)
  if (!item || !item.damageDice) return null

  const feats = loadFeats(sheet)
  const parsed: ParsedDice = parseDiceNotation(item.damageDice)
  const rolls = rollParsedDice(parsed)

  let flatBonus = parsed.flat
  const breakdown: string[] = []

  // STR to damage for melee weapons
  if (item.weaponType === 'melee') {
    const strMod = ds.mods.strength ?? 0
    if (isTwoHanded(item)) {
      const bonus = Math.floor(strMod * 1.5)
      flatBonus += bonus
      if (bonus !== 0) breakdown.push(`STR ${formatMod(bonus)} (1.5x)`)
    } else {
      flatBonus += strMod
      if (strMod !== 0) breakdown.push(`STR ${formatMod(strMod)}`)
    }
  }

  // Flat feat damage bonuses
  for (const feat of feats) {
    for (const effect of feat.effects) {
      if (effect.type !== 'bonus') continue
      const t = effect.target
      const isRelevant =
        t === 'damage' ||
        (t === 'melee_damage' && item.weaponType === 'melee') ||
        (t === 'ranged_damage' && item.weaponType === 'ranged')
      if (!isRelevant) continue

      if (effect.condition) {
        breakdown.push(`(${formatMod(effect.bonus)} ${feat.name} — ${effect.condition})`)
      } else {
        flatBonus += effect.bonus
        breakdown.push(`${feat.name} ${formatMod(effect.bonus)}`)
      }
    }
  }

  // Power Attack / Deadly Aim (optional toggle — show as note)
  for (const feat of feats) {
    for (const effect of feat.effects) {
      if (effect.type !== 'attack_damage_trade') continue
      const scaleFactor = Math.max(1, Math.floor(ds.bab / effect.scalingPerBAB))
      const dmgBonus = effect.damageBonus * scaleFactor
      const twoHandBonus = (effect.twoHandedDamageBonus ?? dmgBonus) * scaleFactor
      if (item.weaponType === 'melee' && isTwoHanded(item) && effect.twoHandedDamageBonus) {
        breakdown.push(`(${formatMod(twoHandBonus)} if ${feat.name})`)
      } else {
        breakdown.push(`(${formatMod(dmgBonus)} if ${feat.name})`)
      }
    }
  }

  // Vital Strike (note)
  for (const feat of feats) {
    for (const effect of feat.effects) {
      if (effect.type !== 'extra_weapon_dice') continue
      const extraNotation = `+${effect.multiplier}x${item.damageDice}`
      breakdown.push(`(${extraNotation} if ${feat.name})`)
    }
  }

  const diceSum = rolls.reduce((a, b) => a + b, 0)
  const total = Math.max(1, diceSum + flatBonus)
  const isBash = item.itemType === 'shield'
  const label = isBash ? `${item.name} (bash)` : `${item.name} Damage`

  return {
    rolls,
    diceNotation: item.damageDice,
    flatBonus,
    bonusBreakdown: breakdown,
    total,
    damageType: item.damageType ?? 'untyped',
    label,
  }
}

// ── Spell damage roll ────────────────────────────────────────

function getSpellDamageEffect(spell: SpellDefinition): (SpellEffect & { type: 'damage' }) | null {
  const effect = spell.effects.find(e => e.type === 'damage')
  return effect as (SpellEffect & { type: 'damage' }) | null
}

export function spellHasDamage(spell: SpellDefinition): boolean {
  return !!getSpellDamageEffect(spell)
}

export function rollSpellDamage(
  spell: SpellDefinition,
  characterLevel: number,
): DamageRollResult | null {
  const effect = getSpellDamageEffect(spell)
  if (!effect) return null

  const baseParsed = parseDiceNotation(effect.dice)
  const breakdown: string[] = []

  let diceCount = baseParsed.count
  if (effect.perCasterLevel) {
    diceCount = Math.min(characterLevel, effect.maxDice ?? characterLevel)
    breakdown.push(`${diceCount}d${baseParsed.sides} (CL ${characterLevel}, max ${effect.maxDice ?? '∞'})`)
  }

  // Magic Missile style: multiple missiles each dealing separate damage
  if (effect.missileCount) {
    const mc = effect.missileCount
    const missiles = Math.min(mc.max, mc.base + Math.floor((characterLevel - 1) / mc.perLevels))
    const missileRolls: number[] = []
    for (let i = 0; i < missiles; i++) {
      const r = rollParsedDice({ count: baseParsed.count, sides: baseParsed.sides, flat: 0 })
      missileRolls.push(...r)
    }
    const flatTotal = baseParsed.flat * missiles
    const diceSum = missileRolls.reduce((a, b) => a + b, 0)
    return {
      rolls: missileRolls,
      diceNotation: `${missiles}x(${effect.dice})`,
      flatBonus: flatTotal,
      bonusBreakdown: [`${missiles} missiles at CL ${characterLevel}`],
      total: Math.max(1, diceSum + flatTotal),
      damageType: effect.damageType,
      label: `${spell.name}`,
    }
  }

  const parsed: ParsedDice = { count: diceCount, sides: baseParsed.sides, flat: baseParsed.flat }
  const rolls = rollParsedDice(parsed)
  const diceSum = rolls.reduce((a, b) => a + b, 0)
  const total = Math.max(1, diceSum + parsed.flat)

  return {
    rolls,
    diceNotation: `${diceCount}d${baseParsed.sides}${parsed.flat ? formatMod(parsed.flat) : ''}`,
    flatBonus: parsed.flat,
    bonusBreakdown: breakdown,
    total,
    damageType: effect.damageType,
    label: `${spell.name}`,
  }
}

// ── Formatting ───────────────────────────────────────────────

function formatMod(val: number): string {
  return val >= 0 ? `+${val}` : `${val}`
}
