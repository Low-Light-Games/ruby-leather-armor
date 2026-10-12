import type { DamageRollResult, ParsedDice } from './dice'
import { parseDiceNotation, rollParsedDice } from './dice'
import type { ItemDefinition } from './pathfinder_items_types'
import type { SpellDefinition, SpellEffect } from './pathfinder_spells_types'
import type { BonusTarget, FeatDefinition } from './pathfinder_feats_types'
import type { AdventureSheet, DerivedStats } from '../types'
import { getItemById } from './pathfinder_items'
import { getFeatById } from './pathfinder_feats'
import { getUnarmedDamageDice } from './pathfinder_unarmed'

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

function loadFeats(sheet: AdventureSheet): FeatDefinition[] {
  const ids = sheet.details?.feats ?? []
  return ids.map(id => getFeatById(id)).filter((f): f is FeatDefinition => !!f)
}

function hasReplaceModifier(feats: FeatDefinition[]): boolean {
  return feats.some(f =>
    f.effects.some(e => e.type === 'replace_modifier' && e.to === 'DEX')
  )
}

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

const MINIMUM_DAMAGE = 1
const TWO_HANDED_STRENGTH_MULTIPLIER = 1.5

function sumOf(rolls: number[]): number {
  return rolls.reduce((a, b) => a + b, 0)
}

// Conditional bonuses are only noted; the player applies them when the condition holds.
function addFeatDamageBonuses(
  feats: FeatDefinition[],
  appliesTo: (target: BonusTarget) => boolean,
  breakdown: string[],
): number {
  let bonus = 0
  for (const feat of feats) {
    for (const effect of feat.effects) {
      if (effect.type !== 'bonus') continue
      if (!appliesTo(effect.target)) continue

      if (effect.condition) {
        breakdown.push(`(${formatMod(effect.bonus)} ${feat.name} — ${effect.condition})`)
      } else {
        bonus += effect.bonus
        breakdown.push(`${feat.name} ${formatMod(effect.bonus)}`)
      }
    }
  }
  return bonus
}

function addBuffDamage(ds: DerivedStats, breakdown: string[]): number {
  const buffDamage = ds.damage_bonus ?? 0
  if (buffDamage !== 0) breakdown.push(`Active buffs ${formatMod(buffDamage)}`)
  return buffDamage
}

// Power Attack and Deadly Aim are opt-in, so they show as notes instead of adding to the total.
function noteAttackDamageTrades(
  feats: FeatDefinition[],
  bab: number,
  wieldedTwoHandedInMelee: boolean,
  breakdown: string[],
): void {
  for (const feat of feats) {
    for (const effect of feat.effects) {
      if (effect.type !== 'attack_damage_trade') continue
      const scaleFactor = Math.max(1, Math.floor(bab / effect.scalingPerBAB))
      const damagePerStep = wieldedTwoHandedInMelee && effect.twoHandedDamageBonus
        ? effect.twoHandedDamageBonus
        : effect.damageBonus
      breakdown.push(`(${formatMod(damagePerStep * scaleFactor)} if ${feat.name})`)
    }
  }
}

function noteExtraWeaponDice(feats: FeatDefinition[], damageDice: string, breakdown: string[]): void {
  for (const feat of feats) {
    for (const effect of feat.effects) {
      if (effect.type !== 'extra_weapon_dice') continue
      breakdown.push(`(+${effect.multiplier}x${damageDice} if ${feat.name})`)
    }
  }
}

function addMeleeStrengthDamage(item: ItemDefinition, strMod: number, breakdown: string[]): number {
  if (isTwoHanded(item)) {
    const bonus = Math.floor(strMod * TWO_HANDED_STRENGTH_MULTIPLIER)
    if (bonus !== 0) breakdown.push(`STR ${formatMod(bonus)} (1.5x)`)
    return bonus
  }
  if (strMod !== 0) breakdown.push(`STR ${formatMod(strMod)}`)
  return strMod
}

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

  if (item.weaponType === 'melee') {
    flatBonus += addMeleeStrengthDamage(item, ds.mods.strength ?? 0, breakdown)
  }

  flatBonus += addFeatDamageBonuses(
    feats,
    target =>
      target === 'damage' ||
      (target === 'melee_damage' && item.weaponType === 'melee') ||
      (target === 'ranged_damage' && item.weaponType === 'ranged'),
    breakdown,
  )
  flatBonus += addBuffDamage(ds, breakdown)
  noteAttackDamageTrades(feats, ds.bab, item.weaponType === 'melee' && isTwoHanded(item), breakdown)
  noteExtraWeaponDice(feats, item.damageDice, breakdown)

  const total = Math.max(MINIMUM_DAMAGE, sumOf(rolls) + flatBonus)
  const isShieldBash = item.itemType === 'shield'
  const label = isShieldBash ? `${item.name} (bash)` : `${item.name} Damage`

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

export function rollUnarmedDamage(
  sheet: AdventureSheet,
  ds: DerivedStats,
): DamageRollResult {
  const diceNotation = getUnarmedDamageDice(sheet.character_class, sheet.level)
  const parsed: ParsedDice = parseDiceNotation(diceNotation)
  const rolls = rollParsedDice(parsed)

  let flatBonus = parsed.flat
  const breakdown: string[] = []

  const strMod = ds.mods.strength ?? 0
  flatBonus += strMod
  if (strMod !== 0) breakdown.push(`STR ${formatMod(strMod)}`)

  const feats = loadFeats(sheet)
  flatBonus += addFeatDamageBonuses(
    feats,
    target => target === 'damage' || target === 'melee_damage',
    breakdown,
  )
  flatBonus += addBuffDamage(ds, breakdown)
  noteAttackDamageTrades(feats, ds.bab, false, breakdown)

  const total = Math.max(MINIMUM_DAMAGE, sumOf(rolls) + flatBonus)

  return {
    rolls,
    diceNotation,
    flatBonus,
    bonusBreakdown: breakdown,
    total,
    damageType: 'bludgeoning',
    label: 'Unarmed Strike',
  }
}

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

  if (effect.missileCount) {
    const { max, base, perLevels } = effect.missileCount
    const missiles = Math.min(max, base + Math.floor((characterLevel - 1) / perLevels))
    const missileRolls: number[] = []
    for (let i = 0; i < missiles; i++) {
      missileRolls.push(...rollParsedDice({ count: baseParsed.count, sides: baseParsed.sides, flat: 0 }))
    }
    const flatTotal = baseParsed.flat * missiles
    return {
      rolls: missileRolls,
      diceNotation: `${missiles}x(${effect.dice})`,
      flatBonus: flatTotal,
      bonusBreakdown: [`${missiles} missiles at CL ${characterLevel}`],
      total: Math.max(MINIMUM_DAMAGE, sumOf(missileRolls) + flatTotal),
      damageType: effect.damageType,
      label: `${spell.name}`,
    }
  }

  const parsed: ParsedDice = { count: diceCount, sides: baseParsed.sides, flat: baseParsed.flat }
  const rolls = rollParsedDice(parsed)
  const total = Math.max(MINIMUM_DAMAGE, sumOf(rolls) + parsed.flat)

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

function formatMod(val: number): string {
  return val >= 0 ? `+${val}` : `${val}`
}
